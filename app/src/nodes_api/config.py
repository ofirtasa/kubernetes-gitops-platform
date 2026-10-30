import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    """Runtime settings, read from environment variables.

    In the cluster: NODE_NAME, POD_NAME and POD_NAMESPACE come from the Downward API,
    APP_ENV and LOG_LEVEL from a ConfigMap, API_KEY from a Secret.
    """

    app_env: str
    log_level: str
    node_name: str | None
    pod_name: str | None
    pod_namespace: str | None
    api_key: str | None
    k8s_timeout_seconds: float

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            app_env=os.getenv("APP_ENV", "local"),
            log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
            node_name=os.getenv("NODE_NAME") or None,
            pod_name=os.getenv("POD_NAME") or None,
            pod_namespace=os.getenv("POD_NAMESPACE") or None,
            api_key=os.getenv("API_KEY") or None,
            k8s_timeout_seconds=float(os.getenv("K8S_TIMEOUT_SECONDS", "5")),
        )
