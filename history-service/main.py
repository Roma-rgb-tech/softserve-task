"""History service.

Owns persistence. Readings arrive from the backend over HTTP and are appended
to Postgres; reads are served back to the backend.

The store is append-only: there is an insert endpoint but no update or delete,
so a monitoring record cannot be rewritten once it lands.
"""

import os
import json
from datetime import datetime
from typing import Optional

import asyncpg
from fastapi import FastAPI, HTTPException

app = FastAPI()
DATABASE_URL = os.getenv("DATABASE_URL", "postgres://postgres:example@postgres:5432/history_db")
pool = None

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
    """The collection time comes from the fetcher and travels through the
    queue. It must survive that trip: if the consumer was down for a while,
    stamping rows with the moment we drained the queue would lose the real
    collection times."""
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None


@app.on_event("startup")
async def startup():
    global pool
    pool = await asyncpg.create_pool(DATABASE_URL, init=_init_connection)
    async with pool.acquire() as conn:
        await conn.execute(CREATE_TABLE_SQL)


@app.on_event("shutdown")
async def shutdown():
    global pool
    if pool:
        await pool.close()


@app.post("/history/events")
async def receive_event(payload: dict):
    """The single write path. The backend calls this after consuming a reading
    from RabbitMQ — this service no longer talks to the broker itself."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")

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
    return {"status": "stored"}


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
