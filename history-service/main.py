"""History service.

Owns persistence. Consumes weather readings from RabbitMQ and appends them to
Postgres, and exposes read-only endpoints for the backend.

The store is deliberately append-only: there are no delete or clear endpoints,
so a monitoring history cannot be rewritten from the outside.
"""

import os
import json
import asyncio
from datetime import datetime, timezone
from typing import Optional
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


def _parse_event_time(raw):
    """The collection time comes from the fetcher inside the message. It must
    survive the queue: if the consumer was down for a while, every backlogged
    message would otherwise be stamped with the moment we drained the queue,
    and the real collection times would be lost."""
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None


async def persist_event(payload: dict):
    """The single write path. Only the RabbitMQ consumer calls this — nothing
    over HTTP can insert, update or remove a row."""
    global pool
    collected_at = _parse_event_time(payload.get("event_time"))
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO requests_history(event_time, path, client_ip, query_params, response_status, response_body) "
            "VALUES (COALESCE($1, now()), $2, $3, $4::jsonb, $5, $6::jsonb)",
            collected_at,
            payload.get("path"),
            payload.get("client_ip"),
            payload.get("query_params") or {},
            payload.get("response_status"),
            payload.get("response_body") or {},
        )


async def consume_weather_events():
    """Background consumer. This is the asynchronous half of the write path:
    the fetcher publishes to `weather.events` and we pick messages up whenever
    we're alive, so a restart on either side never loses a reading — RabbitMQ
    holds the durable message until we come back."""
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
                                await persist_event(json.loads(message.body.decode()))
                            except Exception:
                                # A malformed message shouldn't take the whole
                                # consumer down; it's acked and dropped, and
                                # everything else keeps flowing.
                                pass
        except Exception:
            # Broker not reachable yet (still booting, say) — back off and
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


@app.get("/history/recent")
async def recent(limit: int = 20, offset: int = 0, city: Optional[str] = None):
    """Stored readings, most recent first, paged via limit/offset.

    Filtering by city happens in SQL rather than in the caller, so `limit`
    and `offset` count filtered rows — otherwise paging and the row counter
    would disagree with each other."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    rows = []
    async with pool.acquire() as conn:
        if city:
            recs = await conn.fetch(
                "SELECT id, event_time, path, client_ip, query_params, response_status, response_body "
                "FROM requests_history WHERE query_params->>'city' = $3 "
                "ORDER BY id DESC LIMIT $1 OFFSET $2",
                limit, offset, city,
            )
        else:
            recs = await conn.fetch(
                "SELECT id, event_time, path, client_ip, query_params, response_status, response_body "
                "FROM requests_history ORDER BY id DESC LIMIT $1 OFFSET $2",
                limit, offset,
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
async def count(city: Optional[str] = None):
    """Number of stored readings, optionally for one city. Takes the same
    filter as /history/recent so the UI's "showing N of M" always matches
    what the table is actually displaying."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        if city:
            total = await conn.fetchval(
                "SELECT COUNT(*) FROM requests_history WHERE query_params->>'city' = $1", city
            )
        else:
            total = await conn.fetchval("SELECT COUNT(*) FROM requests_history")
    return {"total": total}
