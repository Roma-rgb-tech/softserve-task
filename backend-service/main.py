import os
import asyncio
from fastapi import FastAPI, Query, Request, HTTPException
import httpx
from typing import Any, Dict, Optional
from datetime import datetime

app = FastAPI()
HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
AIR_QUALITY_API = "https://air-quality-api.open-meteo.com/v1/air-quality"
GEOCODE_API = "https://geocoding-api.open-meteo.com/v1/search"

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


async def log_reading(city_name: str, lat: float, lon: float, reading: Dict[str, Any],
                       client_ip: Optional[str] = None):
    """Send one reading to the History service. Fire-and-forget: a failed
    write here should never break the response to the caller."""
    event = {
        "event_time": datetime.utcnow().isoformat(),
        "path": "/weather",
        "client_ip": client_ip,
        "query_params": {"lat": lat, "lon": lon, "city": city_name},
        "response_status": reading.get("weather_status", 200),
        "response_body": reading,
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            await client.post(f"{HISTORY_BASE}/history/events", json=event)
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


async def poll_watched_cities():
    """Background task: re-fetches every watched city once per
    POLL_INTERVAL_SECONDS, on the backend's own clock. Runs regardless of
    whether anyone has the UI open, and is the only thing that decides
    *when* the public APIs get called."""
    while True:
        for name, coords in list(watched_cities.items()):
            try:
                reading = await fetch_reading(coords["latitude"], coords["longitude"])
                latest_cache[name] = reading
                await log_reading(name, coords["latitude"], coords["longitude"],
                                   reading, client_ip="backend-poller")
            except Exception:
                pass
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


@app.on_event("startup")
async def start_background_poller():
    global _poll_task
    for name in DEFAULT_CITY_NAMES:
        geo = await geocode_city(name)
        if geo:
            register_city(geo.get("name") or name, geo["latitude"], geo["longitude"])
    _poll_task = asyncio.create_task(poll_watched_cities())


@app.on_event("shutdown")
async def stop_background_poller():
    if _poll_task:
        _poll_task.cancel()


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


@app.get("/weather")
async def weather(request: Request,
                  lat: Optional[float] = Query(None), lon: Optional[float] = Query(None),
                  city: Optional[str] = Query(None)):
    """On-demand fetch for one city. Also adds the city to the background
    poll pool, so it keeps getting refreshed automatically afterwards."""
    chosen = None
    if city:
        geo = await geocode_city(city)
        if not geo:
            raise HTTPException(status_code=404, detail=f"City not found: {city}")
        lat = geo["latitude"]
        lon = geo["longitude"]
        chosen = geo.get("name") or city
    if lat is None or lon is None:
        raise HTTPException(status_code=400, detail="Provide either city or lat+lon")

    name = chosen or city or f"{lat},{lon}"
    reading = await fetch_reading(lat, lon)
    latest_cache[name] = reading
    register_city(name, lat, lon)
    await log_reading(name, lat, lon, reading,
                       client_ip=request.client.host if request.client else None)

    history_rows = []
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp_hist = await client.get(f"{HISTORY_BASE}/history/recent?limit=20")
            history_rows = resp_hist.json()
        except Exception:
            pass

    return {"source": "open-meteo", "location_name": name, "payload": reading, "history": history_rows}


@app.get("/cities")
async def list_cities():
    """Names of cities currently in the background polling pool, so the UI
    knows what to render cards for without hardcoding a list."""
    return {"cities": list(watched_cities.keys())}


@app.get("/latest")
async def latest(city: Optional[str] = Query(None)):
    """Instant read of the last background poll — no external call made
    here. Pass ?city=Name for one city, or omit it to get every tracked
    city's latest reading in one response."""
    if city:
        if city not in latest_cache:
            raise HTTPException(status_code=503, detail=f"No reading collected yet for {city}")
        return {"location_name": city, "payload": latest_cache[city]}

    if not latest_cache:
        raise HTTPException(status_code=503, detail="No readings collected yet, try again shortly")
    return {
        "cities": {
            name: {"location_name": name, "payload": reading}
            for name, reading in latest_cache.items()
        }
    }


@app.get("/history/recent")
async def history_recent(limit: int = Query(20, ge=1, le=200)):
    """Proxy endpoint to fetch recent history rows from the History service."""
    url = f"{HISTORY_BASE}/history/recent?limit={limit}"
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