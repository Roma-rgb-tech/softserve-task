"""Backend service.

The only service the UI talks to. It does three things:

  * consumes readings from RabbitMQ and hands them to History for storage
  * session state — ephemeral UI preferences in Redis, keyed by a cookie
  * reads — serves stored readings by proxying the History service

It never calls a public weather API. The fetcher owns that, on its own clock,
so no user action anywhere in the UI can trigger an outbound fetch. It also
exposes no way to modify or delete history: the store is append-only.
"""

import os
import json
import uuid
import asyncio
from typing import Any, Dict, List, Optional
from urllib.parse import quote

import httpx
import aio_pika
import redis.asyncio as aioredis
from fastapi import FastAPI, Query, Request, Response, HTTPException

app = FastAPI()

HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")

# RabbitMQ: the fetcher publishes each reading here and this service consumes
# it. The consumer is a background task inside this process — a piece of code,
# not a separate container, so no extra service-to-service plumbing is needed
# to get a message from the queue into storage.
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://app:example@postgres/")
QUEUE_NAME = os.getenv("WEATHER_EVENTS_QUEUE", "weather.events")
_rmq_connection = None
_consumer_task: Optional[asyncio.Task] = None

# Redis: purely ephemeral UI session state (chart period, filters, selected
# city) — never business data, and never user accounts.
REDIS_URL = os.getenv("REDIS_URL", "redis://postgres:6379/0")
SESSION_COOKIE_NAME = "session_id"
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(60 * 60 * 24 * 30)))  # 30 days
redis_client: Optional[aioredis.Redis] = None

# The monitored cities, fixed by deployment config. The same list the fetcher
# uses; the UI renders a card per entry and cannot change it.
WATCHED_CITIES: List[str] = [
    c.strip() for c in os.getenv("WATCHED_CITIES", "Kyiv,Warsaw,Vilnius").split(",") if c.strip()
]


async def store_reading(payload: dict):
    """Hand one consumed reading to History, which owns the database. This
    service has no DB driver of its own on purpose: persistence stays behind
    a single owner."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(f"{HISTORY_BASE}/history/events", json=payload)
        resp.raise_for_status()


async def consume_weather_events():
    """Background consumer. This is the asynchronous half of the write path:
    the fetcher publishes to `weather.events` and we pick messages up whenever
    we're alive, so a restart on either side never loses a reading — RabbitMQ
    holds the durable message until we come back.

    A message is only acked once History has stored it, so a failure here
    leaves the reading in the queue rather than dropping it."""
    global _rmq_connection
    while True:
        try:
            _rmq_connection = await aio_pika.connect_robust(RABBITMQ_URL)
            async with _rmq_connection:
                channel = await _rmq_connection.channel()
                await channel.set_qos(prefetch_count=10)
                queue = await channel.declare_queue(QUEUE_NAME, durable=True)
                async for message in queue:
                    try:
                        await store_reading(json.loads(message.body.decode()))
                        await message.ack()
                    except json.JSONDecodeError:
                        # Malformed message: acking drops it, since redelivery
                        # would fail the same way forever.
                        await message.ack()
                    except Exception as e:
                        # History unreachable or erroring — requeue and retry,
                        # rather than losing the reading.
                        print(f"[backend] could not store reading: {e}", flush=True)
                        await message.nack(requeue=True)
                        await asyncio.sleep(5)
        except Exception as e:
            # Broker not reachable yet (still booting, say) — back off and
            # retry the connection itself, not each individual message.
            print(f"[backend] broker unavailable: {e}", flush=True)
            await asyncio.sleep(5)


@app.on_event("startup")
async def startup():
    global redis_client, _consumer_task
    redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)
    _consumer_task = asyncio.create_task(consume_weather_events())


@app.on_event("shutdown")
async def shutdown():
    if _consumer_task:
        _consumer_task.cancel()
    if _rmq_connection:
        await _rmq_connection.close()
    if redis_client:
        await redis_client.close()


async def history_get(path: str):
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(f"{HISTORY_BASE}{path}")
        return resp.json()


# --- sessions -------------------------------------------------------------

def _session_key(session_id: str) -> str:
    return f"session:{session_id}"


async def get_or_create_session_id(request: Request, response: Response) -> str:
    """Reads the session cookie if present, otherwise mints a new session — an
    opaque id the browser holds onto, with no authentication behind it. Every
    call refreshes the cookie's max-age, so an active tab keeps its session
    alive while an abandoned one expires from Redis on its own."""
    session_id = request.cookies.get(SESSION_COOKIE_NAME)
    if not session_id:
        session_id = uuid.uuid4().hex
    response.set_cookie(
        SESSION_COOKIE_NAME,
        session_id,
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        samesite="lax",
    )
    return session_id


@app.get("/session")
async def session_bootstrap(request: Request, response: Response):
    """Called once on UI load: ensures a session cookie exists and returns the
    UI state saved for it. An empty dict means "use defaults"."""
    session_id = await get_or_create_session_id(request, response)
    raw = await redis_client.get(_session_key(session_id))
    return {"session_id": session_id, "state": json.loads(raw) if raw else {}}


@app.get("/session/state")
async def session_get_state(request: Request, response: Response):
    session_id = await get_or_create_session_id(request, response)
    raw = await redis_client.get(_session_key(session_id))
    return json.loads(raw) if raw else {}


@app.put("/session/state")
async def session_put_state(request: Request, response: Response, patch: dict):
    """Merges `patch` into the session's stored UI state and refreshes its
    TTL. Only display preferences live here."""
    session_id = await get_or_create_session_id(request, response)
    key = _session_key(session_id)
    raw = await redis_client.get(key)
    state = json.loads(raw) if raw else {}
    state.update(patch)
    await redis_client.set(key, json.dumps(state), ex=SESSION_TTL_SECONDS)
    return state


@app.delete("/session")
async def session_clear(request: Request, response: Response):
    """Drops this session's preferences and issues a fresh session id. Only
    touches Redis — no weather data is affected."""
    session_id = request.cookies.get(SESSION_COOKIE_NAME)
    if session_id:
        await redis_client.delete(_session_key(session_id))
    new_id = uuid.uuid4().hex
    response.set_cookie(
        SESSION_COOKIE_NAME,
        new_id,
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        samesite="lax",
    )
    return {"session_id": new_id, "state": {}}


# --- reads ----------------------------------------------------------------

@app.get("/cities")
async def list_cities():
    """The monitored cities. Fixed configuration — there is no endpoint to add
    or remove one."""
    return {"cities": WATCHED_CITIES}


@app.get("/latest")
async def latest(city: Optional[str] = Query(None)):
    """Latest stored reading per city, taken from the history the fetcher has
    already collected. Nothing here reaches a public API, so refreshing the UI
    can never cause an outbound request."""
    try:
        rows = await history_get("/history/recent?limit=300&offset=0")
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # rows come back newest-first, so the first hit per city is its latest
    newest: Dict[str, Any] = {}
    for row in rows:
        name = (row.get("query_params") or {}).get("city")
        if name and name not in newest:
            newest[name] = row.get("response_body")

    if city:
        if city in newest:
            return {"location_name": city, "payload": newest[city]}
        raise HTTPException(status_code=503, detail=f"No reading collected yet for {city}")

    if not newest:
        raise HTTPException(status_code=503, detail="No readings collected yet, try again shortly")
    return {
        "cities": {
            name: {"location_name": name, "payload": reading}
            for name, reading in newest.items()
        }
    }


@app.get("/history/recent")
async def history_recent(limit: int = Query(20, ge=1, le=1000),
                         offset: int = Query(0, ge=0),
                         city: Optional[str] = Query(None)):
    """Paged history, optionally filtered to one city. Stays synchronous
    HTTP: RabbitMQ carries the write path only, and a queue is the wrong
    shape for a request/response read."""
    url = f"{HISTORY_BASE}/history/recent?limit={limit}&offset={offset}"
    if city:
        url += f"&city={quote(city)}"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(url)
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    return resp.json()


@app.get("/history/count")
async def history_count(city: Optional[str] = Query(None)):
    """Stored reading count, matching the same optional city filter."""
    url = f"{HISTORY_BASE}/history/count"
    if city:
        url += f"?city={quote(city)}"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(url)
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    return resp.json()
