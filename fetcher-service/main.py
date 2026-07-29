"""Fetcher service.

The only component in the system that talks to the public weather APIs.

The city list is fixed by configuration (`WATCHED_CITIES`) — nothing at
runtime can change it, and no user action can make this service fetch. It
resolves those names to coordinates once at startup, then polls on its own
clock and publishes every reading to RabbitMQ.

    Fetcher --(AMQP: weather.events)--> History --> Postgres
"""

import os
import json
import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional

import httpx
import aio_pika
from fastapi import FastAPI

app = FastAPI()

OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
AIR_QUALITY_API = "https://air-quality-api.open-meteo.com/v1/air-quality"
GEOCODE_API = "https://geocoding-api.open-meteo.com/v1/search"

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://app:example@postgres/")
QUEUE_NAME = os.getenv("WEATHER_EVENTS_QUEUE", "weather.events")

# The monitored cities. Deployment configuration, not runtime state.
WATCHED_CITIES: List[str] = [
    c.strip() for c in os.getenv("WATCHED_CITIES", "Kyiv,Warsaw,Vilnius").split(",") if c.strip()
]

# One sweep per hour by default.
POLL_INTERVAL_SECONDS = int(os.getenv("POLL_INTERVAL_SECONDS", "3600"))
# Never record two readings for the same city closer together than this, so a
# restart loop can't flood the history with near-identical rows.
MIN_RECORD_INTERVAL_SECONDS = int(os.getenv("MIN_RECORD_INTERVAL_SECONDS", "3000"))

CURRENT_WEATHER_FIELDS = (
    "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,"
    "pressure_msl,weather_code,wind_speed_10m,wind_direction_10m,is_day"
)
CURRENT_AIR_QUALITY_FIELDS = "pm10,pm2_5,nitrogen_dioxide,ozone,carbon_monoxide"

_rmq_connection: Optional[aio_pika.RobustConnection] = None
_rmq_channel: Optional[aio_pika.Channel] = None
_poll_task: Optional[asyncio.Task] = None

# name -> {"name", "latitude", "longitude"}, resolved once at startup
resolved_cities: Dict[str, Dict[str, Any]] = {}
last_recorded_at: Dict[str, datetime] = {}
last_sweep: Optional[str] = None
sweep_count = 0


async def geocode_city(name: str) -> Optional[Dict[str, Any]]:
    """Resolve one city name to coordinates. Runs only at startup — the list
    is fixed, so this is a one-off resolution of configuration, not something
    a user can trigger."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(GEOCODE_API, params={"name": name, "count": 1})
            j = r.json()
        except Exception:
            return None
    results = (j or {}).get("results") or []
    if not results:
        return None
    top = results[0]
    return {
        "name": top.get("name") or name,
        "latitude": top.get("latitude"),
        "longitude": top.get("longitude"),
    }


async def resolve_all_cities():
    """Fill `resolved_cities` from the configured names. Retries the whole set
    until every city is resolved, because without coordinates a city simply
    cannot be polled."""
    for name in WATCHED_CITIES:
        if name in resolved_cities:
            continue
        geo = await geocode_city(name)
        if geo and geo["latitude"] is not None:
            resolved_cities[geo["name"]] = geo


async def get_rmq_channel() -> Optional[aio_pika.Channel]:
    """Lazily connect/reconnect and cache the channel. Returns None when the
    broker is unreachable, which callers treat as skip-this-round."""
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


async def fetch_reading(lat: float, lon: float) -> Dict[str, Any]:
    """Current weather + air quality for one location, merged into one flat
    reading. Two Open-Meteo endpoints feed the single result downstream
    services work with."""
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


async def publish_reading(city: Dict[str, Any], reading: Dict[str, Any]):
    """Publish one reading to the durable queue. Fire-and-forget: if the
    broker is down the message is dropped this round and the next sweep
    produces a fresh one — a reading is a snapshot, not a command."""
    event = {
        "event_time": datetime.utcnow().isoformat(),
        "path": "/weather",
        "client_ip": "fetcher",
        "query_params": {
            "lat": city["latitude"],
            "lon": city["longitude"],
            "city": city["name"],
        },
        "response_status": reading.get("weather_status", 200),
        "response_body": reading,
    }
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


async def poll_once():
    """One sweep over every configured city."""
    global last_sweep, sweep_count
    if len(resolved_cities) < len(WATCHED_CITIES):
        await resolve_all_cities()

    now = datetime.utcnow()
    for name, city in list(resolved_cities.items()):
        last = last_recorded_at.get(name)
        if last and (now - last).total_seconds() < MIN_RECORD_INTERVAL_SECONDS:
            continue
        try:
            reading = await fetch_reading(city["latitude"], city["longitude"])
            await publish_reading(city, reading)
            last_recorded_at[name] = datetime.utcnow()
        except Exception:
            # One bad city must not stop the sweep for the others.
            continue
    last_sweep = now.isoformat()
    sweep_count += 1


async def poll_loop():
    while True:
        try:
            await poll_once()
        except Exception:
            pass
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


@app.on_event("startup")
async def startup():
    global _poll_task
    await resolve_all_cities()
    _poll_task = asyncio.create_task(poll_loop())


@app.on_event("shutdown")
async def shutdown():
    if _poll_task:
        _poll_task.cancel()
    if _rmq_connection:
        await _rmq_connection.close()


@app.get("/health")
async def health():
    """Observability only — reports what the fetcher has been doing. It never
    triggers a fetch."""
    return {
        "status": "ok",
        "configured_cities": WATCHED_CITIES,
        "resolved_cities": sorted(resolved_cities.keys()),
        "poll_interval_seconds": POLL_INTERVAL_SECONDS,
        "min_record_interval_seconds": MIN_RECORD_INTERVAL_SECONDS,
        "sweeps_completed": sweep_count,
        "last_sweep": last_sweep,
    }
