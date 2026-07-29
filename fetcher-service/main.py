"""Fetcher service.

The only component in the system that talks to the public weather APIs. It
runs on its own clock — nothing in the UI or the backend can make it fetch on
demand — reads the watch list from the History service, and publishes each
reading to RabbitMQ. History consumes from that queue and persists.

    Fetcher --(AMQP: weather.events)--> History --> Postgres
       |
       +--(HTTP read: which cities?)--> History
"""

import os
import json
import asyncio
from datetime import datetime
from typing import Any, Dict, Optional

import httpx
import aio_pika
from fastapi import FastAPI

app = FastAPI()

HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
AIR_QUALITY_API = "https://air-quality-api.open-meteo.com/v1/air-quality"

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://app:example@postgres/")
QUEUE_NAME = os.getenv("WEATHER_EVENTS_QUEUE", "weather.events")

# How often the whole watch list is swept.
POLL_INTERVAL_SECONDS = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))
# Never record two readings for the same city closer together than this,
# regardless of how often the sweep runs.
MIN_RECORD_INTERVAL_SECONDS = int(os.getenv("MIN_RECORD_INTERVAL_SECONDS", "60"))

CURRENT_WEATHER_FIELDS = (
    "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,"
    "pressure_msl,weather_code,wind_speed_10m,wind_direction_10m,is_day"
)
CURRENT_AIR_QUALITY_FIELDS = "pm10,pm2_5,nitrogen_dioxide,ozone,carbon_monoxide"

_rmq_connection: Optional[aio_pika.RobustConnection] = None
_rmq_channel: Optional[aio_pika.Channel] = None
_poll_task: Optional[asyncio.Task] = None

last_recorded_at: Dict[str, datetime] = {}
last_sweep: Optional[str] = None
sweep_count = 0


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


async def load_watch_list() -> list:
    """Read the cities to poll from the History service. A sync HTTP read is
    fine here: it's our own service, and a queue would be the wrong shape for
    a request/response lookup."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            resp = await client.get(f"{HISTORY_BASE}/cities")
            return resp.json()
        except Exception:
            return []


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
    broker is down the message is dropped this round and the next sweep will
    produce a fresh one — the reading is a snapshot, not a command."""
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
    """One sweep of the whole watch list."""
    global last_sweep, sweep_count
    cities = await load_watch_list()
    now = datetime.utcnow()
    for city in cities:
        name = city.get("name")
        if not name:
            continue
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
    _poll_task = asyncio.create_task(poll_loop())


@app.on_event("shutdown")
async def shutdown():
    if _poll_task:
        _poll_task.cancel()
    if _rmq_connection:
        await _rmq_connection.close()


@app.get("/health")
async def health():
    """Observability only — this endpoint reports what the fetcher has been
    doing, it never triggers a fetch."""
    return {
        "status": "ok",
        "poll_interval_seconds": POLL_INTERVAL_SECONDS,
        "min_record_interval_seconds": MIN_RECORD_INTERVAL_SECONDS,
        "sweeps_completed": sweep_count,
        "last_sweep": last_sweep,
        "cities_seen": sorted(last_recorded_at.keys()),
    }
