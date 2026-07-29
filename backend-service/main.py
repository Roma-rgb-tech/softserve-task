import os
import json
import uuid
from fastapi import FastAPI, Query, Request, Response, HTTPException
import httpx
import redis.asyncio as aioredis
from typing import Any, Dict, Optional

app = FastAPI()
HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")
GEOCODE_API = "https://geocoding-api.open-meteo.com/v1/search"

# Redis: purely for ephemeral UI session state (selected chart period,
# filters, toggles) — never for business/weather data.
REDIS_URL = os.getenv("REDIS_URL", "redis://postgres:6379/0")
SESSION_COOKIE_NAME = "session_id"
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(60 * 60 * 24 * 30)))  # 30 days
redis_client: Optional[aioredis.Redis] = None

# Cities registered on first boot if the watch list is still empty. After
# that the list lives in the History service's database, not here.
DEFAULT_CITY_NAMES = [c.strip() for c in os.getenv("WATCHED_CITIES", "Kyiv,Lviv").split(",") if c.strip()]


async def geocode_city(name: str) -> Optional[Dict[str, Any]]:
    """Resolve a city name to latitude/longitude using Open-Meteo geocoding API."""
    params = {"name": name, "count": 1}
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            r = await client.get(GEOCODE_API, params=params)
            j = r.json()
        except Exception:
            return None
    if not j or "results" not in j or not j["results"]:
        return None
    top = j["results"][0]
    return {"name": top.get("name"), "latitude": top.get("latitude"),
            "longitude": top.get("longitude"), "country": top.get("country")}


@app.on_event("startup")
async def startup():
    """Opens the Redis connection and seeds the watch list once. No polling
    happens here — the fetcher service owns every call to the weather API."""
    global redis_client
    redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)
    try:
        existing = await history_get("/cities")
    except Exception:
        existing = []
    if not existing:
        for name in DEFAULT_CITY_NAMES:
            geo = await geocode_city(name)
            if geo:
                await register_city(geo.get("name") or name, geo["latitude"], geo["longitude"])


@app.on_event("shutdown")
async def shutdown():
    if redis_client:
        await redis_client.close()


async def history_get(path: str):
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(f"{HISTORY_BASE}{path}")
        return resp.json()


async def register_city(name: str, lat: float, lon: float):
    """Persist a city into the shared watch list owned by the History
    service. The fetcher reads that list on its next sweep."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        await client.post(
            f"{HISTORY_BASE}/cities",
            json={"name": name, "latitude": lat, "longitude": lon},
        )


def _session_key(session_id: str) -> str:
    return f"session:{session_id}"


async def get_or_create_session_id(request: Request, response: Response) -> str:
    """Reads the session cookie if present, otherwise mints a new session
    (no auth involved — just an opaque id the browser holds onto). Every
    call refreshes the cookie's max-age so an active browser tab keeps its
    session alive; an abandoned one expires from Redis on its own."""
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
    """Called once on UI load. Ensures a session cookie exists and returns
    whatever UI state was previously saved for it (empty dict = defaults)."""
    session_id = await get_or_create_session_id(request, response)
    raw = await redis_client.get(_session_key(session_id))
    state = json.loads(raw) if raw else {}
    return {"session_id": session_id, "state": state}


@app.get("/session/state")
async def session_get_state(request: Request, response: Response):
    session_id = await get_or_create_session_id(request, response)
    raw = await redis_client.get(_session_key(session_id))
    return json.loads(raw) if raw else {}


@app.put("/session/state")
async def session_put_state(request: Request, response: Response, patch: dict):
    """Merges `patch` into the session's stored UI state (chart period,
    filters, toggles — never business data) and refreshes its TTL."""
    session_id = await get_or_create_session_id(request, response)
    key = _session_key(session_id)
    raw = await redis_client.get(key)
    state = json.loads(raw) if raw else {}
    state.update(patch)
    await redis_client.set(key, json.dumps(state), ex=SESSION_TTL_SECONDS)
    return state


@app.delete("/session")
async def session_clear(request: Request, response: Response):
    """Drops the session's stored state and issues a fresh session id —
    used by the UI's 'reset preferences' action."""
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


@app.get("/geocode")
async def geocode_proxy(q: str):
    """Proxy endpoint for geocoding API so UI doesn't call external services directly."""
    params = {"name": q, "count": 5}
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.get(GEOCODE_API, params=params)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=502, detail=str(e))


@app.post("/cities")
async def add_city(city: str = Query(...)):
    """Adds a city to the watch list. This is a configuration change, not a
    data fetch: no weather API call happens here. The fetcher service owns
    every call to the public weather API and will pick this city up on its
    next sweep.

    Only geocoding runs synchronously, because coordinates are needed before
    the city can be polled at all."""
    geo = await geocode_city(city)
    if not geo:
        raise HTTPException(status_code=404, detail=f"City not found: {city}")
    name = geo.get("name") or city
    await register_city(name, geo["latitude"], geo["longitude"])
    return {"status": "watching", "location_name": name}


@app.delete("/cities")
async def remove_city(city: str = Query(...)):
    """Stops watching a city. Rows already stored stay in the database."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        await client.delete(f"{HISTORY_BASE}/cities/{city}")
    return {"status": "removed", "city": city}


@app.get("/cities")
async def list_cities():
    """Names of cities on the watch list, so the UI knows what cards to
    render without hardcoding a list. Read straight from the History
    service, which owns the list."""
    try:
        rows = await history_get("/cities")
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
    return {"cities": [r["name"] for r in rows]}


@app.get("/latest")
async def latest(city: Optional[str] = Query(None)):
    """Serves stored readings only, straight out of the history the fetcher
    has already collected. Nothing here reaches the public weather API, so a
    UI refresh can never trigger an external fetch."""
    try:
        rows = await history_get("/history/recent?limit=300&offset=0")
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # rows are newest-first, so the first hit per city is its latest reading
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
async def history_recent(limit: int = Query(20, ge=1, le=1000), offset: int = Query(0, ge=0)):
    """Proxy endpoint to fetch recent history rows from the History service, paged.
    This stays synchronous HTTP — RabbitMQ is one-directional (write path only),
    reads still go straight to History."""
    url = f"{HISTORY_BASE}/history/recent?limit={limit}&offset={offset}"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(url)
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    return resp.json()


@app.get("/history/count")
async def history_count():
    """Proxy endpoint returning the total number of history rows."""
    url = f"{HISTORY_BASE}/history/count"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(url)
        except Exception as e:
            raise HTTPException(status_code=502, detail=str(e))
    return resp.json()


@app.delete("/history/clear")
async def backend_clear_history():
    url = f"{HISTORY_BASE}/history/clear"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.delete(url)
    return resp.json()


@app.delete("/history/{item_id}")
async def backend_delete_item(item_id: int):
    url = f"{HISTORY_BASE}/history/{item_id}"
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.delete(url)
    return resp.json()