import copy
import json
from pathlib import Path
import unittest
from patch_pool import helm_values, plan


class PoolPlanTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((Path(__file__).parent.parent / "cluster/pool.json").read_text())
        self.live = {"metadata": {"name": "atplus-k8s", "namespace": "arc-runners", "resourceVersion": "123"},
                     "spec": {"template": {"spec": {"containers": [{"name": "runner", "env": [{"name": "KEEP", "value": "keep"}],
                         "resources": {"requests": {"ephemeral-storage": "1Gi"}}}], "initContainers": [{"name": "init-dind-externals"}, {"name": "dind"}],
                         "volumes": [{"name": "work", "emptyDir": {}}]}}}}
        self.image = "ghcr.io/atplus-digital/ci-browser@sha256:" + "a" * 64

    def test_patch_preserves_auth_volumes_and_unrelated_resources(self):
        original = copy.deepcopy(self.live)
        patch = plan(self.live, self.config, self.image)
        self.assertEqual(self.live, original)
        self.assertEqual(patch[0], {"op": "test", "path": "/metadata/resourceVersion", "value": "123"})
        paths = [op["path"] for op in patch]
        self.assertFalse(any("env" in p or "volumes" in p or "githubConfigSecret" in p for p in paths))
        resources = next(op["value"] for op in patch if op["path"] == "/spec/template/spec/containers/0/resources")
        self.assertEqual(resources["requests"]["ephemeral-storage"], "1Gi")
        self.assertEqual(resources["requests"]["cpu"], "1")

    def test_rejects_mutable_images_wrong_pool_and_capacity_growth(self):
        with self.assertRaises(ValueError):
            plan(self.live, self.config, "ghcr.io/atplus-digital/ci-browser:main")
        self.config["maxRunners"] = 25
        with self.assertRaises(ValueError):
            plan(self.live, self.config, self.image)

    def test_helm_customizes_docker_without_duplicate_generated_sidecars(self):
        pod = self.live["spec"]["template"]["spec"]
        pod["containers"][0]["env"] = [
            {"name": "DOCKER_HOST", "value": "unix:///var/run/docker.sock"},
            {"name": "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS", "value": "120"},
        ]
        pod["serviceAccountName"] = "atplus-k8s-gha-rs-no-permission"
        values = helm_values(self.live, self.config, self.image)
        self.assertEqual(values["containerMode"], {"type": ""})
        self.assertNotIn("serviceAccountName", values["template"]["spec"])
        self.assertNotIn("githubConfigSecret", values)
        self.assertEqual(values["template"]["spec"]["containers"][0]["image"], self.image)
        self.assertEqual(values["template"]["spec"]["containers"][0]["env"], pod["containers"][0]["env"])
        self.assertEqual(values["template"]["spec"]["initContainers"][1]["resources"], self.config["dockerResources"])
        pod["containers"][0]["env"].append({"name": "SENSITIVE_CONFIGURATION", "value": "sentinel"})
        with self.assertRaises(ValueError):
            helm_values(self.live, self.config, self.image)
        self.config["maxRunners"] = 24
        self.live["metadata"]["namespace"] = "another-namespace"
        with self.assertRaises(ValueError):
            plan(self.live, self.config, self.image)


if __name__ == "__main__":
    unittest.main()
