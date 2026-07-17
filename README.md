# Weather microservices demo
<img width="1295" height="739" alt="image" src="https://github.com/user-attachments/assets/be9110f3-24d2-4a1d-9921-0ab208ded489" />


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


## Running without Docker (native, no containers)
 
This runs the exact same four components (PostgreSQL, history-service, backend-service, ui-service)
directly on your machine, with no Docker involved.
 
### 0. Prerequisites
 
- Python 3.11+ (with `venv`)
- PostgreSQL 15 installed locally (`postgres` binary + `psql` client)
- nginx installed locally (used only to reproduce the `/api/*` reverse proxy that keeps the UI
  talking exclusively to the backend — the same rule that applies in the Docker setup)
On Debian/Ubuntu:
 
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib nginx python3-venv python3-pip
```
 
On macOS (Homebrew):
 
```bash
brew install postgresql@15 nginx
brew services start postgresql@15
```
 
### 1. Start PostgreSQL and create the database
 
```bash
sudo service postgresql start        # or: brew services start postgresql@15
 
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'example';"
sudo -u postgres createdb history_db
```
 
(The `history-service` will create the `requests_history` table automatically on startup —
no manual schema migration needed.)
 
### 2. Run the History service (port 8001)
 
```bash
cd history-service
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
 
export DATABASE_URL="postgres://postgres:example@localhost:5432/history_db"
uvicorn main:app --host 0.0.0.0 --port 8001
```
 
Keep this terminal open. In a new terminal, continue with step 3.
 
### 3. Run the Backend / Proxy service (port 8000)
 
```bash
cd backend-service
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
 
export HISTORY_BASE="http://localhost:8001"
uvicorn main:app --host 0.0.0.0 --port 8000
```
 
> Note: the backend reads the `HISTORY_BASE` env var (defaults to `http://history:8001`, the
> Docker service name). `docker-compose.yml` currently sets `HISTORY_URL` instead, which the
> code never reads — it only works in Docker by coincidence, because the default host `history`
> matches the compose service name. Worth fixing to `HISTORY_BASE` for clarity.
 
### 4. Serve the UI through nginx (port 8080), proxying `/api/*` to the backend
 
The shipped `ui-service/nginx.conf` proxies to `http://backend:8000/`, which is a Docker DNS
name and won't resolve outside Docker. For a local run, use a copy with `localhost` instead:
 
```bash
cd ui-service
sed 's/backend:8000/127.0.0.1:8000/' nginx.conf > local-nginx.conf
mkdir -p logs
nginx -p "$(pwd)" -c local-nginx.conf
```
 
Open the UI at:
 
```text
http://localhost:8080
```
 
To stop this local nginx instance later: `nginx -p "$(pwd)" -c local-nginx.conf -s stop`
 
### Quick alternative (skip nginx entirely)
 
If you don't want to install nginx, you can add CORS to the backend (e.g.
`fastapi.middleware.cors.CORSMiddleware`, allow `http://localhost:8080`) and serve
`ui-service/index.html` with `python3 -m http.server 8080`. You'd then need to point the
frontend's `fetch()` calls at `http://localhost:8000/...` instead of `/api/...`. This is
faster for a quick check, but it no longer enforces "UI talks only to the backend" the same
way the nginx proxy does — the nginx route above is the closer match to the assignment's
architecture rule.
 
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
