from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from kubernetes.client.exceptions import ApiException

from nodes_api.config import Settings
from nodes_api.main import create_app


def make_node(name, zone, ready=True):
    return SimpleNamespace(
        metadata=SimpleNamespace(
            name=name,
            labels={
                "topology.kubernetes.io/zone": zone,
                "node.kubernetes.io/instance-type": "c7i-flex.large",
            },
        ),
        status=SimpleNamespace(
            conditions=[SimpleNamespace(type="Ready", status="True" if ready else "False")],
            addresses=[SimpleNamespace(type="InternalIP", address=f"10.0.0.{len(name)}")],
            node_info=SimpleNamespace(kubelet_version="v1.37.0"),
        ),
    )


def make_settings(**overrides):
    values = {
        "app_env": "test",
        "log_level": "INFO",
        "node_name": "node-b",
        "pod_name": "nodes-api-abc",
        "pod_namespace": "dev",
        "api_key": None,
        "k8s_timeout_seconds": 5,
    }
    return Settings(**(values | overrides))


@pytest.fixture
def core_api():
    api = MagicMock()
    api.list_node.return_value.items = [
        make_node("node-b", "eu-north-1b"),
        make_node("node-a", "eu-north-1a", ready=False),
    ]
    return api


def client_for(core_api, **overrides):
    return TestClient(create_app(make_settings(**overrides), core_api=core_api))


def test_health(core_api):
    with client_for(core_api) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready(core_api):
    with client_for(core_api) as client:
        assert client.get("/ready").status_code == 200


def test_nodes_marks_current_node(core_api):
    with client_for(core_api) as client:
        body = client.get("/nodes").json()
    assert body["current_node"] == "node-b"
    assert body["count"] == 2
    assert [n["name"] for n in body["nodes"]] == ["node-a", "node-b"]
    assert [n["current"] for n in body["nodes"]] == [False, True]
    assert body["nodes"][0]["ready"] is False
    assert body["nodes"][1]["zone"] == "eu-north-1b"


def test_nodes_kubernetes_error_returns_502(core_api):
    core_api.list_node.side_effect = ApiException(status=403, reason="Forbidden")
    with client_for(core_api) as client:
        response = client.get("/nodes")
    assert response.status_code == 502


def test_nodes_requires_api_key_when_configured(core_api):
    with client_for(core_api, api_key="s3cret") as client:
        assert client.get("/nodes").status_code == 401
        assert client.get("/nodes", headers={"X-API-Key": "wrong"}).status_code == 401
        assert client.get("/nodes", headers={"X-API-Key": "s3cret"}).status_code == 200
        # Probes must never need the key.
        assert client.get("/health").status_code == 200


def test_metrics_use_route_template(core_api):
    with client_for(core_api) as client:
        client.get("/health")
        metrics = client.get("/metrics").text
    assert 'http_requests_total{method="GET",route="/health",status="200"}' in metrics
