#!/usr/bin/env python3
"""Atualiza somente capacidade, recursos e imagens do pool ARC existente."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def plan(live, config, image):
    if not re.fullmatch(r"ghcr\.io/atplus-digital/ci-browser@sha256:[0-9a-f]{64}", image):
        raise ValueError("A imagem precisa ser ci-browser por digest imutável")
    if (live["metadata"]["name"], live["metadata"]["namespace"]) != (config["name"], config["namespace"]):
        raise ValueError("O objeto não corresponde ao pool configurado")
    if not 0 <= config["minRunners"] <= config["maxRunners"] <= 24:
        raise ValueError("Capacidade fora do orçamento aprovado de 24 runners")
    spec = live["spec"]["template"]["spec"]
    containers, init = spec["containers"], spec["initContainers"]
    runner = next(i for i, c in enumerate(containers) if c["name"] == "runner")
    docker = next(i for i, c in enumerate(init) if c["name"] == "dind")
    externals = next(i for i, c in enumerate(init) if c["name"] == "init-dind-externals")
    patch = [{"op": "test", "path": "/metadata/resourceVersion", "value": live["metadata"]["resourceVersion"]}]
    for field in ("minRunners", "maxRunners"):
        patch.append({"op": "add", "path": f"/spec/{field}", "value": config[field]})
    for path in (f"containers/{runner}", f"initContainers/{externals}"):
        patch.append({"op": "add", "path": f"/spec/template/spec/{path}/image", "value": image})
        patch.append({"op": "add", "path": f"/spec/template/spec/{path}/imagePullPolicy", "value": "IfNotPresent"})
    for path, container, resources in (
        (f"containers/{runner}", containers[runner], config["runnerResources"]),
        (f"initContainers/{docker}", init[docker], config["dockerResources"]),
    ):
        merged = dict(container.get("resources", {}))
        for section, values in resources.items():
            merged[section] = {**merged.get(section, {}), **values}
        patch.append({"op": "add", "path": f"/spec/template/spec/{path}/resources", "value": merged})
    spread = list(spec.get("topologySpreadConstraints", []))
    if not any(x.get("topologyKey") == "kubernetes.io/hostname" for x in spread):
        spread.append({"maxSkew": 1, "topologyKey": "kubernetes.io/hostname", "whenUnsatisfiable": "ScheduleAnyway",
                       "labelSelector": {"matchLabels": {"actions.github.com/scale-set-name": config["name"]}}})
        patch.append({"op": "add", "path": "/spec/template/spec/topologySpreadConstraints", "value": spread})
    return patch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    config = json.loads((Path(__file__).parent.parent / "cluster/pool.json").read_text())
    kubectl = ["kubectl", "--kubeconfig", args.kubeconfig, "--request-timeout=30s", "-n", config["namespace"]]
    live = json.loads(subprocess.check_output(kubectl + ["get", "autoscalingrunnerset", config["name"], "-o", "json"]))
    patch = plan(live, config, args.image)
    if args.dry_run:
        print(json.dumps(patch, indent=2))
    else:
        subprocess.run(kubectl + ["patch", "autoscalingrunnerset", config["name"], "--type=json", "--patch", json.dumps(patch)], check=True)


if __name__ == "__main__":
    main()
