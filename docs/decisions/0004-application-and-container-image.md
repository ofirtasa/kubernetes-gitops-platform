# 0004. Application stack and container image

- Status: accepted
- Date: 2026-10-30

## Context

The service exposes `GET /health` and `GET /nodes`. `/nodes` lists the cluster nodes and marks
the node the pod runs on. It reads the Kubernetes API with its own ServiceAccount, so it must
be small, observable and safe to run under a restricted securityContext.

## Decision

- **Language:** Python 3.13 with FastAPI and the official `kubernetes` client. The project and
  its lock file are managed by `uv`, so CI and the image install the same versions.
- **Endpoints:**
  - `/health` is liveness and does no I/O.
  - `/ready` is readiness.
  - `/nodes` returns `current: true` for the pod's own node, identified by `NODE_NAME` from the
    Downward API (`spec.nodeName`).
  - `/metrics` serves Prometheus metrics, labelled by route template to keep cardinality low.
- **Least privilege:** the only Kubernetes call is `list` on `nodes`, with a 5 s timeout.
  API errors return `502` and increment `k8s_api_errors_total`.
- **Optional API key:** when the Secret file at `API_KEY_FILE` exists, `/nodes` requires the
  `X-API-Key` header, compared in constant time.
  - The key is mounted as a file, not an env var, and read on each request. A rotated Secret
    applies without a restart.
  - The probes stay open.
- **Logs:** one JSON object per line on stdout.
- **Image:**
  - A multi-stage build: dependencies are installed in `python:3.13-slim-trixie`.
  - The runtime image is `gcr.io/distroless/python3-debian13:nonroot`: no shell and no
    package manager, running as UID 65532.
  - The image runs as a single uvicorn process. Kubernetes scales by replicas, not by workers.

## Consequences

- Distroless leaves no shell to `kubectl exec` into. Debugging uses `kubectl debug` with an
  ephemeral container.
- The small package set keeps Trivy findings low and lets the pod run with
  `readOnlyRootFilesystem` and all capabilities dropped.
- The distroless Python minor version must match the builder's (3.13).
