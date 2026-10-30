import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    """Runtime settings, read from environment variables.

    In the cluster: NODE_NAME, POD_NAME and POD_NAMESPACE come from the Downward API,
    APP_ENV and LOG_LEVEL from a ConfigMap; API_KEY_FILE points at a mounted Secret.
    """

    app_env: str
    log_level: str
    node_name: str | None
    pod_name: str | None
    pod_namespace: str | None
    api_key_file: str | None
    k8s_timeout_seconds: float

    def read_api_key(self) -> str | None:
        """Read on every call, so a rotated Secret applies without a restart."""
        if not self.api_key_file:
            return None
        try:
            return Path(self.api_key_file).read_text().strip() or None
        except FileNotFoundError:
            return None

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            app_env=os.getenv("APP_ENV", "local"),
            log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
            node_name=os.getenv("NODE_NAME") or None,
            pod_name=os.getenv("POD_NAME") or None,
            pod_namespace=os.getenv("POD_NAMESPACE") or None,
            api_key_file=os.getenv("API_KEY_FILE") or None,
            k8s_timeout_seconds=float(os.getenv("K8S_TIMEOUT_SECONDS", "5")),
        )
