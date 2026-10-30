from typing import Any

from kubernetes import client, config
from kubernetes.config.config_exception import ConfigException

ZONE_LABEL = "topology.kubernetes.io/zone"
INSTANCE_TYPE_LABEL = "node.kubernetes.io/instance-type"


def load_kube_config() -> None:
    """In a pod: the ServiceAccount token. Locally: the current kubeconfig context."""
    try:
        config.load_incluster_config()
    except ConfigException:
        config.load_kube_config()


def _is_ready(node: Any) -> bool:
    return any(c.type == "Ready" and c.status == "True" for c in node.status.conditions or [])


def _internal_ip(node: Any) -> str | None:
    return next((a.address for a in node.status.addresses or [] if a.type == "InternalIP"), None)


def list_nodes(api: client.CoreV1Api, current_node: str | None, timeout: float) -> list[dict]:
    """Returns one entry per node; `current` is true for the node this pod runs on."""
    nodes = api.list_node(_request_timeout=timeout).items
    result = [
        {
            "name": n.metadata.name,
            "current": n.metadata.name == current_node,
            "ready": _is_ready(n),
            "zone": (n.metadata.labels or {}).get(ZONE_LABEL),
            "instance_type": (n.metadata.labels or {}).get(INSTANCE_TYPE_LABEL),
            "internal_ip": _internal_ip(n),
            "kubelet_version": n.status.node_info.kubelet_version,
        }
        for n in nodes
    ]
    return sorted(result, key=lambda n: n["name"])
