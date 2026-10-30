# Build stage: resolve and install dependencies from the lock file.
FROM python:3.13-slim-trixie AS builder

COPY --from=ghcr.io/astral-sh/uv:0.13.6 /uv /usr/local/bin/uv

WORKDIR /build
COPY pyproject.toml uv.lock ./
RUN uv export --frozen --no-dev --no-emit-project --format requirements-txt -o requirements.txt \
 && uv pip install --no-cache --target /install -r requirements.txt

COPY src/ /install/

# Runtime stage: no shell, no package manager, runs as UID 65532.
FROM gcr.io/distroless/python3-debian13:nonroot

WORKDIR /app
COPY --from=builder /install /app
ENV PYTHONPATH=/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER 65532:65532
EXPOSE 8000

ENTRYPOINT ["python3", "-m", "uvicorn", "--factory", "nodes_api.main:create_app", \
            "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
