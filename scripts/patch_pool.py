#!/usr/bin/env python3
"""Atualiza somente capacidade, recursos e imagens do pool ARC existente."""
import argparse
import copy
import json
from pathlib import Path
import re
import subprocess


def docker_network_args(args, mtu):
    if not isinstance(mtu, int) or not 1280 <= mtu <= 1480:
        raise ValueError("MTU Docker fora do intervalo validado para os pods Calico")
    result, index = [], 0
    option = "bridge=com.docker.network.driver.mtu="
    while index < len(args):
        value = args[index]
        if value == "--mtu":
            index += 2
            continue
        if value.startswith("--mtu=") or value.startswith("--default-network-opt=" + option):
            index += 1
            continue
        if value == "--default-network-opt" and index + 1 < len(args) and args[index + 1].startswith(option):
            index += 2
            continue
        result.append(value)
        index += 1
    return result + [f"--mtu={mtu}", f"--default-network-opt={option}{mtu}"]


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
    patch.append({"op": "add", "path": f"/spec/template/spec/initContainers/{docker}/args",
                  "value": docker_network_args(init[docker].get("args", []), config["dockerNetworkMtu"])})
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
    parser.add_argument("--helm", default="helm", help="Executável Helm usado para persistir a configuração da release")
    parser.add_argument("--patch-only", action="store_true", help="Emergência: altera somente o objeto Kubernetes")
    args = parser.parse_args()
    config = json.loads((Path(__file__).parent.parent / "cluster/pool.json").read_text())
    kubectl = ["kubectl", "--kubeconfig", args.kubeconfig, "--request-timeout=30s", "-n", config["namespace"]]
    live = json.loads(subprocess.check_output(kubectl + ["get", "autoscalingrunnerset", config["name"], "-o", "json"]))
    patch = plan(live, config, args.image)
    if args.dry_run:
        print(json.dumps(patch, indent=2))
    elif args.patch_only:
        subprocess.run(kubectl + ["patch", "autoscalingrunnerset", config["name"], "--type=json", "--patch", json.dumps(patch)], check=True)
    else:
        values = helm_values(live, config, args.image)
        subprocess.run([args.helm, "upgrade", config["name"],
                        "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set",
                        "--version", "0.14.2", "--kubeconfig", args.kubeconfig,
                        "--namespace", config["namespace"], "--reuse-values", "--values", "-", "--hide-notes"],
                       input=json.dumps(values), text=True, check=True)


def helm_values(live, config, image):
    """Conserva o template existente sem ler Secrets; as credenciais são referências."""
    template = copy.deepcopy(live["spec"]["template"])
    for op in plan(live, config, image):
        prefix = "/spec/template/"
        if not op["path"].startswith(prefix):
            continue
        keys = op["path"][len(prefix):].split("/")
        target = template
        for key in keys[:-1]:
            target = target[int(key)] if isinstance(target, list) else target[key]
        target[keys[-1]] = copy.deepcopy(op["value"])
    pod = template["spec"]
    if pod.get("serviceAccountName") == config["name"] + "-gha-rs-no-permission":
        del pod["serviceAccountName"]
    allowed_env = {"DOCKER_HOST", "DOCKER_TLS_CERTDIR", "DOCKER_GROUP_GID", "RUNNER_WAIT_FOR_DOCKER_IN_SECONDS"}
    for container in pod["containers"] + pod.get("initContainers", []):
        for env in container.get("env", []):
            if "value" in env and env["name"] not in allowed_env:
                raise ValueError("Variável literal fora da lista pública; revise o template antes de persistir")
    return {"minRunners": config["minRunners"], "maxRunners": config["maxRunners"],
            "containerMode": {"type": ""}, "template": template}


if __name__ == "__main__":
    main()
