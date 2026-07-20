# Weather microservices demo

<img width="1676" height="891" alt="image" src="https://github.com/user-attachments/assets/3d11903a-e60e-41d3-bb78-36846b101255" />

This repository implements a small Weather microservice demo using Docker Compose (with a Vagrant/VM alternative).
It is designed to show a front-end service, a backend/orchestration service, a history persistence service, and a PostgreSQL database.

## Architecture

The system is composed of four services:

- `ui-service` — static UI served by nginx on port `8080`. Also reverse-proxies `/api/*` to the backend.
- `backend-service` — FastAPI backend on port `8000` that handles city lookups and weather requests, and orchestrates calls to the public API and the history service.
- `history-service` — FastAPI service on port `8001` that stores request events in PostgreSQL.
- `postgres` — PostgreSQL database on port `5432`.

### Service boundaries

- The **UI** never calls the public weather API or the database directly. It only talks to the backend, through the `/api/*` path exposed by its own nginx.
- The **Backend** is the single orchestration point: it is the only component that calls the public Open-Meteo APIs (weather, air quality, geocoding), and the only component that sends events to the History service. It also runs a background poller that refreshes a set of "watched" cities on its own clock (`POLL_INTERVAL_SECONDS`), independent of whether anyone has the UI open.
- The **History service** owns persistence. It is the only component that talks to PostgreSQL, and it exposes its own endpoints for storing and reading history — the backend proxies to them rather than querying the database itself.
- **PostgreSQL** is only ever reached through the History service in normal operation. It is exposed on `5432` in Docker Compose purely for local debugging (see [Database inspection](#database-inspection)).

### Request flow

```
UI → Backend → Open-Meteo (weather + air quality + geocoding)
            → History service → PostgreSQL
```

## Accessing the API

There are two ways to reach the backend, and the URL path differs between them:

| Access point | Base URL | Path prefix |
|---|---|---|
| Through the UI's nginx proxy | `http://localhost:8080` | `/api/*` (nginx strips `/api/` before forwarding) |
| Directly against the backend container | `http://localhost:8000` | no prefix |

Example — the same endpoint, both ways:

```bash
curl "http://localhost:8080/api/weather?city=Kyiv" | jq .
curl "http://localhost:8000/weather?city=Kyiv" | jq .
```

The frontend itself always calls `/api/*` (never the backend port directly), so it works the same whether you open it via Docker Compose or Vagrant.

## Running locally (Docker)

### Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)

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

## Running with Vagrant (Alternative)

If you want to run the stack inside virtual machines using Vagrant (configured for ARM64/Apple Silicon via QEMU or VMware), follow these steps:

### Prerequisites
- Install [Vagrant](https://www.vagrantup.com/)
- Install a compatible provider (e.g., `vagrant-qemu` or VMware Fusion)

### Start the cluster
Bring up all the virtual machines defined in the `Vagrantfile`:

```bash
vagrant up --provider=qemu
```

### VM layout

Each service runs in its own VM with a static, reachable IP:

| VM | Hostname | IP | SSH port |
|---|---|---|---|
| PostgreSQL | `postgres` | `192.168.105.10` | `2222` |
| History service | `history` | `192.168.105.11` | `2223` |
| Backend service | `backend` | `192.168.105.12` | `2224` |
| UI | `ui` | `192.168.105.13` | `2225` |

Open the frontend at `http://192.168.105.13`. SSH into a VM with `vagrant ssh <name>` (or `ssh -p <port> vagrant@127.0.0.1`).

### Check status and stop

Check the current state of the virtual machines:

```bash
vagrant status
```

Stop and destroy the virtual machines when you are done:

```bash
vagrant destroy -f
```

## Key endpoints

Paths below are relative — prepend `http://localhost:8000` for a direct backend call, or `http://localhost:8080/api` when going through the UI's nginx proxy.

Backend endpoints:

- `GET /geocode?q=<city>` — proxy geocoding lookup (UI never calls the public geocoding API directly)
- `GET /weather?city=<city>` or `?lat=<lat>&lon=<lon>` — fetch current weather + air quality for a city, log it to history, and return recent history alongside it
- `GET /cities` — list cities currently in the background polling pool
- `GET /latest?city=<city>` — instant read of the last background poll result, no external call made
- `GET /history/recent?limit=<n>` — proxy to fetch recent history from the History service
- `DELETE /history/clear` — clear all history
- `DELETE /history/{id}` — delete a single history record

History service endpoints (internal, reached via `http://history:8001` inside the network):

- `POST /history/events` — store a request event
- `GET /history/recent` — list recent history records
- `DELETE /history/clear` — clear history
- `DELETE /history/{id}` — delete one record

## Verify the stack

```bash
curl "http://localhost:8080/api/geocode?q=Kyiv" | jq .
curl "http://localhost:8080/api/weather?city=Kyiv" | jq .
curl "http://localhost:8080/api/history/recent?limit=5" | jq .
```

If you open the UI, front-end autocomplete and weather/history calls should go through `/api/*` and not call the public API directly.

## Environment variables

| Variable | Service | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | history | — (set in compose/Vagrant) | PostgreSQL connection string |
| `HISTORY_BASE` | backend | `http://history:8001` | Base URL the backend uses to reach the History service |
| `POLL_INTERVAL_SECONDS` | backend | `60` (`10` in this repo's compose file) | How often watched cities are re-polled in the background |
| `WATCHED_CITIES` | backend | `Kyiv,Lviv` | Cities polled automatically on startup |
| `MAX_WATCHED_CITIES` | backend | `8` (`3600` in this repo's compose file) | Cap on how many cities the poll pool can hold before evicting the oldest non-default entry |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | postgres | `postgres` / `example` / `history_db` | Database credentials |

## Database inspection

Connect to PostgreSQL:

```bash
psql -h localhost -U postgres -d history_db -W
```

(password: `example`)

```sql
SELECT id, event_time, path, query_params, response_status FROM requests_history ORDER BY id DESC LIMIT 10;
```

## Notes

- The app uses `POSTGRES_PASSWORD=example` and database `history_db`. This is fine for local/learning use only — do not reuse these credentials anywhere else.
- `/weather` currently returns both `payload` (the fresh reading) and recent `history` in one response.
- `docker-compose.yml` exposes PostgreSQL on `5432` for local inspection; in the Vagrant setup, `pg_hba.conf` is opened to the `192.168.105.0/24` subnet instead.