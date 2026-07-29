"""Backend service.

The only service the UI talks to. It does two things:

  * session state — ephemeral UI preferences in Redis, keyed by a cookie
  * reads — serves stored readings by proxying the History service

It never calls a public weather API. The fetcher owns that, on its own clock,
so no user action anywhere in the UI can trigger an outbound fetch. It also
exposes no way to modify or delete history: the store is append-only.
"""

import os
import json
import uuid
from typing import Any, Dict, List, Optional
from urllib.parse import quote

import httpx
import redis.asyncio as aioredis
from fastapi import FastAPI, Query, Request, Response, HTTPException

app = FastAPI()

HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")

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


@app.on_event("startup")
async def startup():
    global redis_client
    redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)


@app.on_event("shutdown")
async def shutdown():
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
