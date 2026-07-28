import os
import json
import uuid
import asyncio
from fastapi import FastAPI, Query, Request, Response, HTTPException
import httpx
import aio_pika
import redis.asyncio as aioredis
from typing import Any, Dict, Optional
from datetime import datetime

app = FastAPI()
HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
AIR_QUALITY_API = "https://air-quality-api.open-meteo.com/v1/air-quality"
GEOCODE_API = "https://geocoding-api.open-meteo.com/v1/search"

# RabbitMQ: this is the async replacement for the old direct HTTP call to
# History. We publish here; History consumes from the same durable queue.
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://app:example@postgres/")
QUEUE_NAME = os.getenv("WEATHER_EVENTS_QUEUE", "weather.events")
_rmq_connection: Optional[aio_pika.RobustConnection] = None
_rmq_channel: Optional[aio_pika.Channel] = None

# Redis: purely for ephemeral UI session state (selected chart period,
# filters, toggles) — never for business/weather data.
REDIS_URL = os.getenv("REDIS_URL", "redis://postgres:6379/0")
SESSION_COOKIE_NAME = "session_id"
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", str(60 * 60 * 24 * 30)))  # 30 days
redis_client: Optional[aioredis.Redis] = None

# How often each watched city is re-polled, on the backend's own clock.
POLL_INTERVAL_SECONDS = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))

# Safety cap so an unbounded stream of manual searches can't grow the
# background poll list forever.
MAX_WATCHED_CITIES = int(os.getenv("MAX_WATCHED_CITIES", "8"))

# Cities polled automatically at startup, independent of any UI action.
# Extra cities get added to the pool by manual searches (see register_city).
DEFAULT_CITY_NAMES = [c.strip() for c in os.getenv("WATCHED_CITIES", "Kyiv,Lviv").split(",") if c.strip()]

# name -> {"name", "latitude", "longitude"}. Insertion order is preserved by
# the dict, which register_city() relies on when evicting the oldest entry.
watched_cities: Dict[str, Dict[str, Any]] = {}

# name -> last successful merged reading (weather + air quality).
# This is what GET /latest serves without calling Open-Meteo again.
latest_cache: Dict[str, Dict[str, Any]] = {}

# Minimum gap between two recorded readings for the same city. Guards against
# duplicate history rows when the poller and a fresh city registration land
# close together.
MIN_RECORD_INTERVAL_SECONDS = int(os.getenv("MIN_RECORD_INTERVAL_SECONDS", "600"))
last_recorded_at: Dict[str, datetime] = {}

_poll_task: Optional[asyncio.Task] = None

# Open-Meteo's newer "current=" parameter (as opposed to the older
# current_weather=true flag) is what lets us pull humidity/pressure/etc in
# the same call as temperature and wind.
CURRENT_WEATHER_FIELDS = (
    "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,"
    "pressure_msl,weather_code,wind_speed_10m,wind_direction_10m,is_day"
)
CURRENT_AIR_QUALITY_FIELDS = "pm10,pm2_5,nitrogen_dioxide,ozone,carbon_monoxide"


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


async def fetch_reading(lat: float, lon: float) -> Dict[str, Any]:
    """Fetch current weather + current air quality for one location and
    merge them into a single flat reading. Two separate Open-Meteo APIs
    feed into the one result the rest of the app works with."""
    weather_params = {"latitude": lat, "longitude": lon, "current": CURRENT_WEATHER_FIELDS}
    air_params = {"latitude": lat, "longitude": lon, "current": CURRENT_AIR_QUALITY_FIELDS}

    async with httpx.AsyncClient(timeout=10.0) as client:
        weather_resp = await client.get(OPEN_METEO, params=weather_params)
        weather_data = weather_resp.json()

        air_data: Dict[str, Any] = {}
        air_status = None
        try:
            air_resp = await client.get(AIR_QUALITY_API, params=air_params)
            air_status = air_resp.status_code
            air_data = air_resp.json()
        except Exception:
            pass

    current = weather_data.get("current", {}) or {}
    air_current = air_data.get("current", {}) or {}

    return {
        "time": current.get("time"),
        "temperature": current.get("temperature_2m"),
        "humidity": current.get("relative_humidity_2m"),
        "apparent_temperature": current.get("apparent_temperature"),
        "precipitation": current.get("precipitation"),
        "pressure": current.get("pressure_msl"),
        "weathercode": current.get("weather_code"),
        "windspeed": current.get("wind_speed_10m"),
        "winddirection": current.get("wind_direction_10m"),
        "is_day": current.get("is_day"),
        "air_quality": {
            "pm10": air_current.get("pm10"),
            "pm2_5": air_current.get("pm2_5"),
            "nitrogen_dioxide": air_current.get("nitrogen_dioxide"),
            "ozone": air_current.get("ozone"),
            "carbon_monoxide": air_current.get("carbon_monoxide"),
        },
        "weather_status": weather_resp.status_code,
        "air_quality_status": air_status,
    }


async def get_rmq_channel() -> Optional[aio_pika.Channel]:
    """Lazily connect/reconnect to RabbitMQ and cache the channel. Returns
    None if the broker is unreachable right now — callers treat that as a
    skip-this-round, not a fatal error (matches the fire-and-forget contract
    the old HTTP version had)."""
    global _rmq_connection, _rmq_channel
    if _rmq_channel and not _rmq_channel.is_closed:
        return _rmq_channel
    try:
        _rmq_connection = await aio_pika.connect_robust(RABBITMQ_URL)
        _rmq_channel = await _rmq_connection.channel()
        await _rmq_channel.declare_queue(QUEUE_NAME, durable=True)
        return _rmq_channel
    except Exception:
        return None


async def log_reading(city_name: str, lat: float, lon: float, reading: Dict[str, Any],
                       client_ip: Optional[str] = None):
    """Publish one reading to RabbitMQ instead of calling History directly.
    This is the async path the mentors asked for: Fetcher (this service)
    publishes, History consumes and persists whenever it's available —
    fire-and-forget from our side, same as the old httpx call was."""
    event = {
        "event_time": datetime.utcnow().isoformat(),
        "path": "/weather",
        "client_ip": client_ip,
        "query_params": {"lat": lat, "lon": lon, "city": city_name},
        "response_status": reading.get("weather_status", 200),
        "response_body": reading,
    }
    try:
        channel = await get_rmq_channel()
        if not channel:
            return
        await channel.default_exchange.publish(
            aio_pika.Message(
                body=json.dumps(event).encode(),
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
            ),
            routing_key=QUEUE_NAME,
        )
    except Exception:
        pass


def register_city(name: str, lat: float, lon: float):
    """Add or refresh a city in the background-poll pool. If we're over the
    cap, evict the oldest city that isn't one of the permanent defaults —
    default cities are never evicted by search traffic."""
    watched_cities[name] = {"name": name, "latitude": lat, "longitude": lon}
    if len(watched_cities) > MAX_WATCHED_CITIES:
        for existing in list(watched_cities.keys()):
            if existing not in DEFAULT_CITY_NAMES:
                del watched_cities[existing]
                break


async def poll_one_city(name: str):
    """Fetch + record one city, respecting MIN_RECORD_INTERVAL_SECONDS so we
    never write two rows for the same city within a short window. This is the
    single place that calls the public weather API."""
    coords = watched_cities.get(name)
    if not coords:
        return
    last = last_recorded_at.get(name)
    now = datetime.utcnow()
    if last and (now - last).total_seconds() < MIN_RECORD_INTERVAL_SECONDS:
        return
    try:
        reading = await fetch_reading(coords["latitude"], coords["longitude"])
        latest_cache[name] = reading
        last_recorded_at[name] = now
        await log_reading(name, coords["latitude"], coords["longitude"],
                           reading, client_ip="backend-poller")
    except Exception:
        pass


async def poll_watched_cities():
    """Background task: re-fetches every watched city once per
    POLL_INTERVAL_SECONDS, on the backend's own clock. Runs regardless of
    whether anyone has the UI open, and is the only thing that decides
    *when* the public APIs get called."""
    while True:
        for name in list(watched_cities.keys()):
            await poll_one_city(name)
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


@app.on_event("startup")
async def start_background_poller():
    global _poll_task, redis_client
    redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)
    for name in DEFAULT_CITY_NAMES:
        geo = await geocode_city(name)
        if geo:
            register_city(geo.get("name") or name, geo["latitude"], geo["longitude"])
    _poll_task = asyncio.create_task(poll_watched_cities())


@app.on_event("shutdown")
async def stop_background_poller():
    if _poll_task:
        _poll_task.cancel()
    if _rmq_connection:
        await _rmq_connection.close()
    if redis_client:
        await redis_client.close()


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
    """Adds a city to the watched pool. This is a configuration change, not
    a data fetch: no weather API call happens here. The background poller
    owns every call to the public API and will pick this city up on its own
    schedule (and immediately once, so the UI isn't blank for an hour).

    Only geocoding runs synchronously, because we need coordinates before
    the city can be polled at all."""
    geo = await geocode_city(city)
    if not geo:
        raise HTTPException(status_code=404, detail=f"City not found: {city}")
    name = geo.get("name") or city
    register_city(name, geo["latitude"], geo["longitude"])
    # Kick the poller once for just this city so the first reading lands
    # promptly; this runs on the backend's own clock, not on the UI's.
    asyncio.create_task(poll_one_city(name))
    return {"status": "watching", "location_name": name}


@app.delete("/cities")
async def remove_city(city: str = Query(...)):
    """Stops watching a city. Historical rows already stored stay in the DB."""
    watched_cities.pop(city, None)
    latest_cache.pop(city, None)
    return {"status": "removed", "city": city}


@app.get("/cities")
async def list_cities():
    """Names of cities currently in the background polling pool, so the UI
    knows what to render cards for without hardcoding a list."""
    return {"cities": list(watched_cities.keys())}


async def latest_from_history(city: str) -> Optional[Dict[str, Any]]:
    """Read the most recent stored reading for a city out of the History
    service. Used so the UI still has data after a backend restart — no
    external weather API call is involved."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(f"{HISTORY_BASE}/history/recent?limit=200&offset=0")
            for row in resp.json():
                if (row.get("query_params") or {}).get("city") == city:
                    return row.get("response_body")
        except Exception:
            pass
    return None


@app.get("/latest")
async def latest(city: Optional[str] = Query(None)):
    """Serves stored data only — the in-memory cache first, then the history
    DB. Nothing here ever reaches out to the public weather API, so a UI
    refresh can never trigger an external fetch."""
    if city:
        if city in latest_cache:
            return {"location_name": city, "payload": latest_cache[city]}
        stored = await latest_from_history(city)
        if stored:
            latest_cache[city] = stored
            return {"location_name": city, "payload": stored}
        raise HTTPException(status_code=503, detail=f"No reading collected yet for {city}")

    if not latest_cache:
        raise HTTPException(status_code=503, detail="No readings collected yet, try again shortly")
    return {
        "cities": {
            name: {"location_name": name, "payload": reading}
            for name, reading in latest_cache.items()
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