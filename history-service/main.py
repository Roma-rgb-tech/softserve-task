import os
import json
from fastapi import FastAPI, HTTPException
import asyncpg

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

@app.on_event("startup")
async def startup():
    global pool
    pool = await asyncpg.create_pool(DATABASE_URL)
    async with pool.acquire() as conn:
        await conn.execute(CREATE_TABLE_SQL)

@app.on_event("shutdown")
async def shutdown():
    global pool
    if pool:
        await pool.close()

@app.post("/history/events")
async def receive_event(payload: dict):
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO requests_history(event_time, path, client_ip, query_params, response_status, response_body) VALUES (now(), $1, $2, $3::jsonb, $4, $5::jsonb)",
            payload.get("path"),
            payload.get("client_ip"),
            json.dumps(payload.get("query_params") or {}),
            payload.get("response_status"),
            json.dumps(payload.get("response_body") or {})
        )
    return {"status": "ok"}


@app.get("/history/recent")
async def recent(limit: int = 20):
    """Return recent history rows (most recent first)."""
    global pool
    if not pool:
        raise HTTPException(status_code=500, detail="DB not initialized")
    rows = []
    async with pool.acquire() as conn:
        recs = await conn.fetch(
            "SELECT id, event_time, path, client_ip, query_params, response_status, response_body FROM requests_history ORDER BY id DESC LIMIT $1",
            limit,
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
