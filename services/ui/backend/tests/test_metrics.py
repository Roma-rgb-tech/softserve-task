from fastapi import FastAPI
from fastapi.testclient import TestClient

from ui_service import metrics


def sample(name: str, labels: dict[str, str]) -> float:
    value = metrics.REGISTRY.get_sample_value(name, labels)
    return value or 0.0


def make_app() -> FastAPI:
    app = FastAPI()
    metrics.instrument(app, excluded=("/health",))

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/items/{item_id}")
    def item(item_id: int) -> dict[str, int]:
        return {"id": item_id}

    return app


def test_requests_are_counted_by_route_template_not_raw_path() -> None:
    client = TestClient(make_app())
    labels = {"handler": "/items/{item_id}", "method": "GET", "status": "2xx"}
    before = sample("http_requests_total", labels)

    client.get("/items/1")
    client.get("/items/2")

    assert sample("http_requests_total", labels) == before + 2
    assert sample("http_requests_total", {**labels, "handler": "/items/1"}) == 0


def test_excluded_routes_are_not_counted() -> None:
    client = TestClient(make_app())
    labels = {"handler": "/health", "method": "GET", "status": "2xx"}

    client.get("/health")

    assert sample("http_requests_total", labels) == 0


def test_unknown_paths_share_one_series() -> None:
    client = TestClient(make_app())
    labels = {"handler": "unmatched", "method": "GET", "status": "4xx"}
    before = sample("http_requests_total", labels)

    client.get("/no/such/page")

    assert sample("http_requests_total", labels) == before + 1
