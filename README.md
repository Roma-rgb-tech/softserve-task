# Weather microservices demo
<img width="1315" height="599" alt="image" src="https://github.com/user-attachments/assets/40e741fe-3163-4967-b3f3-bf590766fc4f" />

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
