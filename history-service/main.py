import os
import json
import asyncio
from fastapi import FastAPI, HTTPException
import asyncpg
import aio_pika

app = FastAPI()
DATABASE_URL = os.getenv("DATABASE_URL", "postgres://postgres:example@postgres:5432/history_db")
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://app:example@postgres/")
QUEUE_NAME = os.getenv("WEATHER_EVENTS_QUEUE", "weather.events")
pool = None
_rmq_connection = None
_consumer_task = None

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS requests_history (
  id SERIAL PRIMARY KEY,
  event_time TIMESTAMPTZ DEFAULT now(),
  path TEXT,
  client_ip TEXT,
  query_params JSONB,
  response_status INT,
  response_body JSONB
);

CREATE TABLE IF NOT EXISTS watched_cities (
  name TEXT PRIMARY KEY,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  added_at TIMESTAMPTZ DEFAULT now()
);
"""


async def _init_connection(conn):
    """asyncpg returns JSONB columns as raw text by default. Without this,
    every jsonb value comes back as a Python str instead of a dict/list,
    which then gets double-encoded when FastAPI serializes the response."""
    await conn.set_type_codec(
        "jsonb",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
    )


async def persist_event(payload: dict):
    """Single write path used by both the RabbitMQ consumer and the legacy
    HTTP endpoint, so an event is stored identically either way."""
    global pool
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO requests_history(event_time, path, client_ip, query_params, response_status, response_body) VALUES (now(), $1, $2, $3::jsonb, $4, $5::jsonb)",
            payload.get("path"),
            payload.get("client_ip"),
            payload.get("query_params") or {},
            payload.get("response_status"),
            payload.get("response_body") or {}
        )


async def consume_weather_events():
    """Background consumer: this is the async replacement for the old
    Backend -> History HTTP call. Backend now publishes to `weather.events`
    instead of calling us directly; we pick messages up whenever we're
    alive, so a restart on either side never loses an event — RabbitMQ
    just holds the durable message until we come back."""
    global _rmq_connection
    while True:
        try:
            _rmq_connection = await aio_pika.connect_robust(RABBITMQ_URL)
            async with _rmq_connection:
                channel = await _rmq_connection.channel()
                await channel.set_qos(prefetch_count=10)
                queue = await channel.declare_queue(QUEUE_NAME, durable=True)
                async with queue.iterator() as it:
                    async for message in it:
                        async with message.process():
                            try:
                                payload = json.loads(message.body.decode())
                                await persist_event(payload)
                            except Exception:
                                # A malformed message shouldn't take the whole
                                # consumer down; it's acked (via message.process())
                                # and dropped, everything else keeps flowing.
                                pass
        except Exception:
            # Broker not reachable yet (e.g. still booting) — back off and
            # retry the connection itself, not each individual message.
            await asyncio.sleep(5)


@app.on_event("startup")
async def startup():
    global pool, _consumer_task
    pool = await asyncpg.create_pool(DATABASE_URL, init=_init_connection)
    async with pool.acquire() as conn:
        await conn.execute(CREATE_TABLE_SQL)
    _consumer_task = asyncio.create_task(consume_weather_events())

@app.on_event("shutdown")
async def shutdown():
    global pool, _consumer_task
    if _consumer_task:
        _consumer_task.cancel()
    if _rmq_connection:
        await _rmq_connection.close()
    if pool:
        await pool.close()

@app.post("/history/events")
async def receive_event(payload: dict):
    """Legacy direct-write endpoint. No longer called by Backend (it now
    publishes to RabbitMQ instead) — kept only for manual testing/debugging
    so you can POST a synthetic event without a broker running."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    await persist_event(payload)
    return {"status": "ok"}


@app.get("/history/recent")
async def recent(limit: int = 20, offset: int = 0):
    """Return recent history rows (most recent first), paged via limit/offset."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    rows = []
    async with pool.acquire() as conn:
        recs = await conn.fetch(
            "SELECT id, event_time, path, client_ip, query_params, response_status, response_body FROM requests_history ORDER BY id DESC LIMIT $1 OFFSET $2",
            limit,
            offset,
        )
        for r in recs:
            rows.append({
                "id": r["id"],
                "event_time": r["event_time"].isoformat() if r["event_time"] else None,
                "path": r["path"],
                "client_ip": r["client_ip"],
                "query_params": r["query_params"],
                "response_status": r["response_status"],
                "response_body": r["response_body"],
            })
    return rows


@app.get("/history/count")
async def count():
    """Total number of history rows, used by the UI to know when to stop paging."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        total = await conn.fetchval("SELECT COUNT(*) FROM requests_history")
    return {"total": total}


# --- watched cities -------------------------------------------------------
# The watch list lives here rather than in memory anywhere else: the backend
# writes to it when a user adds a city, and the fetcher reads it on every
# poll cycle. Persisting it means a restart of either service doesn't lose
# the cities someone asked to track.

@app.get("/cities")
async def list_watched():
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        recs = await conn.fetch(
            "SELECT name, latitude, longitude FROM watched_cities ORDER BY added_at"
        )
    return [{"name": r["name"], "latitude": r["latitude"], "longitude": r["longitude"]}
            for r in recs]


@app.post("/cities")
async def add_watched(payload: dict):
    """Idempotent: re-adding a city just refreshes its coordinates."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    name = payload.get("name")
    lat = payload.get("latitude")
    lon = payload.get("longitude")
    if not name or lat is None or lon is None:
        raise HTTPException(status_code=400, detail="name, latitude and longitude are required")
    async with pool.acquire() as conn:
        await conn.execute(
            """INSERT INTO watched_cities(name, latitude, longitude) VALUES ($1, $2, $3)
               ON CONFLICT (name) DO UPDATE SET latitude = $2, longitude = $3""",
            name, float(lat), float(lon),
        )
    return {"status": "watching", "name": name}


@app.delete("/cities/{name}")
async def remove_watched(name: str):
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        await conn.execute("DELETE FROM watched_cities WHERE name = $1", name)
    return {"status": "removed", "name": name}


@app.delete("/history/clear")
async def clear_history():
    """Delete all history rows."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        await conn.execute("TRUNCATE requests_history RESTART IDENTITY")
    return {"status": "cleared"}


@app.delete("/history/{item_id}")
async def delete_item(item_id: int):
    """Delete single history row by id."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        await conn.execute("DELETE FROM requests_history WHERE id = $1", item_id)
    return {"status": "deleted", "id": item_id}