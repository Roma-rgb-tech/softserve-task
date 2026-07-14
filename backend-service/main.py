import os
from fastapi import FastAPI, Query, BackgroundTasks, Request, HTTPException
import httpx
from typing import Any, Dict, Optional
from datetime import datetime

app = FastAPI()
HISTORY_BASE = os.getenv("HISTORY_BASE", "http://history:8001")
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"
GEOCODE_API = "https://geocoding-api.open-meteo.com/v1/search"


async def send_history_event(payload: Dict[str, Any]):
    url = f"{HISTORY_BASE}/history/events"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            await client.post(url, json=payload)
        except Exception:
            pass


async def geocode_city(name: str) -> Optional[Dict[str, Any]]:
    """Resolve a city name to latitude/longitude using Open-Meteo geocoding API.
    Returns dict with keys 'name', 'latitude', 'longitude' or None if not found.
    """
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
    return {"name": top.get("name"), "latitude": top.get("latitude"), "longitude": top.get("longitude"), "country": top.get("country")}


@app.get("/weather")
async def weather(request: Request, background_tasks: BackgroundTasks,
                  lat: Optional[float] = Query(None), lon: Optional[float] = Query(None), city: Optional[str] = Query(None)):
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

    params = {"latitude": lat, "longitude": lon, "current_weather": True}
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(OPEN_METEO, params=params)
        data = resp.json()

    event = {
        "event_time": datetime.utcnow().isoformat(),
        "path": str(request.url.path),
        "client_ip": request.client.host if request.client else None,
        "query_params": {"lat": lat, "lon": lon, "city": city},
        "response_status": resp.status_code,
        "response_body": data
    }
    background_tasks.add_task(send_history_event, event)

    result = {"source": "open-meteo", "payload": data}
    if chosen:
        result["location_name"] = chosen
    return result


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
