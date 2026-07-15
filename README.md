# Weather microservices demo

This repository implements a small Weather microservice demo using Docker Compose.
It is designed to show a front-end service, a backend/orchestration service, a history persistence service, and a PostgreSQL database.

## Architecture

The system is composed of four services:

- `ui-service` — static UI served by nginx on port `8080`.
- `backend-service` — FastAPI backend on port `8000` that handles city lookups and weather requests.
- `history-service` — FastAPI service on port `8001` that stores request events in PostgreSQL.
- `postgres` — PostgreSQL database on port `5432`.

The UI only communicates with the backend via `/api/*`.
The backend is the only component that calls the public Open-Meteo APIs and the only component that sends events to the history service.

## Running locally

Start the full stack:

```bash
docker-compose up --build -d
```

Open the frontend at:

```text
http://localhost:8080
```

Stop and remove containers and volumes:

```bash
docker-compose down -v
```

## Key endpoints

Backend endpoints (via `http://localhost:8000`):

- `GET /api/geocode?q=<city>` — proxy geocoding lookup
- `GET /api/weather?city=<city>` — fetch current weather and recent history
- `GET /api/history/recent?limit=<n>` — fetch recent history
- `DELETE /api/history/clear` — clear all history
- `DELETE /api/history/{id}` — delete a history record

History service endpoints (via `http://localhost:8001`):

- `POST /history/events` — store a request event
- `GET /history/recent` — list recent history records
- `DELETE /history/clear` — clear history
- `DELETE /history/{id}` — delete one record

## Verify the stack

After startup, run these checks:

```bash
curl "http://localhost:8000/geocode?q=Kyiv" | jq .
curl "http://localhost:8000/weather?city=Kyiv" | jq .
curl "http://localhost:8000/history/recent?limit=5" | jq .
```

If you open the UI, front-end autocomplete and weather/history calls should go through `/api/*` and not call the public API directly.

## Database inspection

Connect to PostgreSQL:

```bash
psql -h localhost -U postgres -d history_db -W
SELECT id, event_time, path, query_params, response_status FROM requests_history ORDER BY id DESC LIMIT 10;
```

## Notes

- The app uses `POSTGRES_PASSWORD=example` and database `history_db`.
- `/weather` currently returns both `payload` and recent `history` in one response.
- `docker-compose.yml` exposes PostgreSQL on `5432` for local inspection.
