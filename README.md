# Weather microservices demo

This is a minimal multi-service application for a learning assignment. It contains:

- `ui` — static HTML served by nginx that calls `/api/weather` on the backend
- `backend` — FastAPI service that queries Open-Meteo and forwards events to `history`
- `history` — FastAPI service that stores request events in PostgreSQL
- `postgres` — PostgreSQL database

Run with:

```bash
docker-compose up --build
```

Open http://localhost:8080 

To inspect DB (psql):

```bash
psql -h localhost -U postgres -d history_db -W
SELECT * FROM requests_history ORDER BY id DESC LIMIT 10;
```
