import hmac
import logging
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from kubernetes import client
from kubernetes.client.exceptions import ApiException
from prometheus_client import make_asgi_app
from urllib3.exceptions import HTTPError

from nodes_api import k8s
from nodes_api.config import Settings
from nodes_api.logging_config import configure_logging
from nodes_api.metrics import HTTP_REQUEST_DURATION, HTTP_REQUESTS, K8S_API_ERRORS

logger = logging.getLogger("nodes_api")


def create_app(settings: Settings | None = None, core_api: client.CoreV1Api | None = None):
    settings = settings or Settings.from_env()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if core_api is None:
            k8s.load_kube_config()
            app.state.core_api = client.CoreV1Api()
        else:
            app.state.core_api = core_api
        fields = {"env": settings.app_env, "node": settings.node_name}
        logger.info("started", extra={"fields": fields})
        yield

    app = FastAPI(title="nodes-api", lifespan=lifespan, docs_url=None, redoc_url=None)
    app.mount("/metrics", make_asgi_app())

    @app.middleware("http")
    async def observe(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        elapsed = time.perf_counter() - start
        # Route template, not the raw path, keeps metric cardinality bounded.
        route = getattr(request.scope.get("route"), "path", "unmatched")
        if route != "/metrics":
            HTTP_REQUESTS.labels(request.method, route, response.status_code).inc()
            HTTP_REQUEST_DURATION.labels(request.method, route).observe(elapsed)
            logger.info(
                "request",
                extra={
                    "fields": {
                        "method": request.method,
                        "path": request.url.path,
                        "status": response.status_code,
                        "duration_ms": round(elapsed * 1000, 1),
                    }
                },
            )
        return response

    def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
        # Node names and IPs are infrastructure details: /nodes is not anonymous in the cluster.
        api_key = settings.read_api_key()
        if api_key and not hmac.compare_digest(x_api_key or "", api_key):
            raise HTTPException(status_code=401, detail="invalid or missing X-API-Key header")

    @app.get("/health")
    def health() -> dict:
        """Liveness: the process is up and serving."""
        return {"status": "ok"}

    @app.get("/ready")
    def ready(request: Request) -> dict:
        """Readiness: startup finished and the Kubernetes client is configured."""
        if getattr(request.app.state, "core_api", None) is None:
            raise HTTPException(status_code=503, detail="not ready")
        return {"status": "ready"}

    @app.get("/nodes", dependencies=[Depends(require_api_key)])
    def nodes(request: Request) -> dict:
        try:
            items = k8s.list_nodes(
                request.app.state.core_api, settings.node_name, settings.k8s_timeout_seconds
            )
        except (ApiException, HTTPError) as exc:
            K8S_API_ERRORS.inc()
            logger.exception("listing nodes failed")
            raise HTTPException(status_code=502, detail="Kubernetes API request failed") from exc
        return {
            "current_node": settings.node_name,
            "pod": settings.pod_name,
            "namespace": settings.pod_namespace,
            "environment": settings.app_env,
            "count": len(items),
            "nodes": items,
        }

    return app
