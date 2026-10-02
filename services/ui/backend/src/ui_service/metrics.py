"""Prometheus metrics of the UI service.

They are served on a port of their own (METRICS_PORT): the API port is public
behind the ingress, and the catch-all page route would answer /metrics anyway.
"""

from __future__ import annotations

from time import perf_counter

from fastapi import FastAPI, Request
from prometheus_client import (
    GC_COLLECTOR,
    PLATFORM_COLLECTOR,
    PROCESS_COLLECTOR,
    CollectorRegistry,
    Counter,
    Histogram,
    start_http_server,
)

# A registry of the service's own rather than the global one, so the two
# services never collide when they share a process, as they do under pytest.
REGISTRY = CollectorRegistry()

for collector in (PROCESS_COLLECTOR, PLATFORM_COLLECTOR, GC_COLLECTOR):
    REGISTRY.register(collector)

REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests handled, by route template, method and status class.",
    ["handler", "method", "status"],
    registry=REGISTRY,
)

LATENCY = Histogram(
    "http_request_duration_seconds",
    "Time to produce the response, by route template.",
    ["handler", "method"],
    registry=REGISTRY,
)


def instrument(app: FastAPI, excluded: tuple[str, ...] = ()) -> None:
    """Count and time every request by the route that answered it.

    The label is the route template ("/v1/observations"), never the raw path,
    so the number of series stays bounded whatever visitors type.
    """

    @app.middleware("http")
    async def record(request: Request, call_next):
        started = perf_counter()
        status = 500

        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            route = request.scope.get("route")
            handler = getattr(route, "path", "unmatched")

            if handler not in excluded:
                REQUESTS.labels(handler, request.method, f"{status // 100}xx").inc()
                LATENCY.labels(handler, request.method).observe(perf_counter() - started)


def serve(port: int) -> None:
    """Start the metrics endpoint, or do nothing when port is 0."""
    if port:
        start_http_server(port, registry=REGISTRY)
