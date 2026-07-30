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
from datetime import datetime, timezone
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

# Kept for /health so a stalled collector is visible instead of silent.
last_error: Optional[str] = None
last_published: Optional[str] = None
publish_failures = 0

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


async def drop_rmq():
    """Forget the cached connection so the next call builds a fresh one."""
    global _rmq_connection, _rmq_channel
    _rmq_channel = None
    if _rmq_connection:
        try:
            await _rmq_connection.close()
        except Exception:
            pass
    _rmq_connection = None


async def get_rmq_channel() -> Optional[aio_pika.Channel]:
    """Return a usable channel, opening one if needed.

    `is_closed` alone is not enough: a channel can report open while its
    transport is already gone ("No active transport in channel"), and a
    cached one in that state fails every publish forever. Anything that
    doesn't look healthy is thrown away and rebuilt."""
    global _rmq_connection, _rmq_channel, last_error
    if (_rmq_channel is not None
            and not _rmq_channel.is_closed
            and _rmq_connection is not None
            and not _rmq_connection.is_closed):
        return _rmq_channel

    await drop_rmq()
    try:
        _rmq_connection = await aio_pika.connect_robust(RABBITMQ_URL)
        _rmq_channel = await _rmq_connection.channel()
        await _rmq_channel.declare_queue(QUEUE_NAME, durable=True)
        return _rmq_channel
    except Exception as e:
        last_error = f"connect: {e}"
        print(f"[fetcher] cannot reach broker: {e}", flush=True)
        await drop_rmq()
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


async def publish_reading(city: Dict[str, Any], reading: Dict[str, Any]) -> bool:
    """Publish one reading to the durable queue.

    Tries twice: a channel that went stale between sweeps only reveals itself
    on the failed publish, and rebuilding it there is what stops a single bad
    channel from silently ending collection for good."""
    global last_error, last_published, publish_failures
    event = {
        "event_time": datetime.now(timezone.utc).isoformat(),
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
    message = aio_pika.Message(
        body=json.dumps(event).encode(),
        delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
    )

    for attempt in (1, 2):
        channel = await get_rmq_channel()
        if not channel:
            break
        try:
            await channel.default_exchange.publish(message, routing_key=QUEUE_NAME)
            last_published = datetime.now(timezone.utc).isoformat()
            last_error = None
            return True
        except Exception as e:
            last_error = f"publish {city['name']} (attempt {attempt}): {e}"
            print(f"[fetcher] publish failed for {city['name']}: {e}", flush=True)
            await drop_rmq()

    publish_failures += 1
    return False


async def poll_once():
    """One sweep over every configured city."""
    global last_sweep, sweep_count, last_error
    if len(resolved_cities) < len(WATCHED_CITIES):
        await resolve_all_cities()

    now = datetime.utcnow()
    for name, city in list(resolved_cities.items()):
        last = last_recorded_at.get(name)
        if last and (now - last).total_seconds() < MIN_RECORD_INTERVAL_SECONDS:
            continue
        try:
            reading = await fetch_reading(city["latitude"], city["longitude"])
            # Only mark the city as recorded if the message actually left, so
            # a broker outage doesn't create an hour-long hole in the history.
            if await publish_reading(city, reading):
                last_recorded_at[name] = datetime.utcnow()
        except Exception as e:
            # One bad city must not stop the sweep for the others.
            last_error = f"fetch {name}: {e}"
            print(f"[fetcher] fetch failed for {name}: {e}", flush=True)
            continue
    last_sweep = now.isoformat()
    sweep_count += 1


async def poll_loop():
    global last_error
    while True:
        try:
            await poll_once()
        except Exception as e:
            # The loop itself must never die: a sweep that raises still has to
            # be followed by the next one an hour later.
            last_error = f"sweep: {e}"
            print(f"[fetcher] sweep failed: {e}", flush=True)
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
        "status": "degraded" if last_error else "ok",
        "configured_cities": WATCHED_CITIES,
        "resolved_cities": sorted(resolved_cities.keys()),
        "poll_interval_seconds": POLL_INTERVAL_SECONDS,
        "min_record_interval_seconds": MIN_RECORD_INTERVAL_SECONDS,
        "sweeps_completed": sweep_count,
        "last_sweep": last_sweep,
        "last_published": last_published,
        "publish_failures": publish_failures,
        "last_error": last_error,
        "broker_connected": bool(_rmq_channel and not _rmq_channel.is_closed),
    }