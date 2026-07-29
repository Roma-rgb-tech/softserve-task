# Weather microservices demo

A small weather dashboard built from cooperating services: a UI, a backend/proxy, a
history service, PostgreSQL for persistence, Redis for UI sessions, and RabbitMQ for
asynchronous messaging between the backend and the history service.

Each service runs as a Docker container, and each container runs on its own Vagrant VM
bridged onto the home LAN, so every machine has a real address you can reach from a
phone or another laptop on the same router.

## Architecture

```
                                     Open-Meteo (weather · air quality)
                                            ▲
                                            │ only the fetcher calls it
                                            │
Browser ──▶ UI (nginx) ──▶ Backend ──▶ Redis│   Fetcher ──(AMQP)──▶ RabbitMQ
                              │             │      │                   │
                              │             └──────┘                   ▼
                              └──── HTTP reads ────────────────▶  History ──▶ PostgreSQL
                                                                      ▲
                                            Fetcher reads the watch list ┘
```

| Service | Port | Role |
|---|---|---|
| `ui-service` | 80 | Static dashboard served by nginx; reverse-proxies `/api/*` to the backend |
| `backend-service` | 8000 | UI-facing API: sessions, city registration, history reads. Never calls the weather API |
| `fetcher-service` | 8002 | The only component that calls the public weather API; polls on its own clock and publishes to RabbitMQ |
| `history-service` | 8001 | Owns persistence: the history rows and the watch list. Consumes from RabbitMQ |
| `postgres` | 5432 | Relational store for the request history |
| `redis` | 6379 | Ephemeral UI session state (no user accounts, no business data) |
| `rabbitmq` | 5672 / 15672 | Durable `weather.events` queue + management UI |

### Rules the design follows

**No UI action ever triggers a call to the public API.** Clicking around the dashboard
only reads stored data. Adding a city is a *configuration* change (`POST /cities`): it
registers the city in the watch list, and the fetcher service decides when to fetch.
Geocoding is the single exception, because coordinates are needed before a city can be
polled at all.

**Writes are asynchronous, reads are synchronous.** The fetcher publishes each reading to
the durable `weather.events` queue instead of calling History over HTTP. History consumes
whenever it is alive — restart either side and RabbitMQ holds the message until the
consumer comes back. Reads (`/history/recent`, `/history/count`) stay plain HTTP, since a
queue is one-directional and RPC-over-AMQP would be overkill here.

**Duplicate readings are suppressed.** `MIN_RECORD_INTERVAL_SECONDS` (default 600) means
two rows for the same city can never land within ten minutes of each other, however often
the poller runs or how many times a city is re-registered.

**Redis holds UI preferences only.** Session state is the chart period, the city filter,
the rows-per-page choice, and the featured city — never weather data. There is no
authentication and no user management; the session is an opaque cookie id with a sliding
30-day TTL.

## What the UI does

Open the dashboard and you get a live weather console. The page background is a gradient
sky that repaints to match the featured city's real conditions and time of day — daytime
blue, muted indigo at night, grey-blue for rain, darker violet for storms.

**Hero panel.** The featured city shown large: temperature, "feels like", a written
condition, and an animated scene that reflects the actual weather code — the sun rotates
its rays, the moon drifts among stars, rain falls from a cloud, lightning flashes during a
storm. Below it, four readouts: wind, humidity, pressure, PM2.5.

**City cards.** One card per watched city, with temperature, condition, a weather glyph,
and four air-quality bars (PM2.5, PM10, NO₂, O₃) coloured green/amber/red by threshold.
Click any card to feature it — the hero and the page sky follow, and the choice is saved
to your session.

**Search.** Type a city and get autocomplete suggestions (arrow keys and Enter work).
Selecting one registers the city for watching; the first reading arrives shortly after,
once the poller picks it up.

**Temperature chart.** A trend line built from the stored history, with a period selector
(24 hours / 7 days / 30 days). The choice persists across refreshes.

**Request log.** Every reading the backend has recorded, newest first: id, timestamp,
city, temperature, humidity, NO₂, and HTTP status. Filter by city, choose 20/50/100 rows,
page through the whole log with "Load more", delete a single row, or clear everything.

**Session persistence.** Change the chart period, the filter, the row count, or the
featured city, then refresh the page — everything comes back exactly as you left it,
because the state lives in Redis keyed by your session cookie. Open the same URL in a
private window and you get an independent session with default settings.

## Running with Vagrant

### Prerequisites

- [Vagrant](https://www.vagrantup.com/)
- The `vagrant-qemu` plugin: `vagrant plugin install vagrant-qemu`
- QEMU: `brew install qemu`

### Configure your network first

The VMs take static addresses on your home subnet, so two values must match your router:

```ruby
BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")       # your active adapter
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.88")    # FIRST THREE octets only
```

Find them with:

```bash
route get default | grep interface   # → the adapter, e.g. en0
ipconfig getifaddr en0               # → e.g. 192.168.88.15, so prefix is 192.168.88
```

Make sure the octets used below (`.50`–`.53`) fall **outside your router's DHCP pool**,
or you will eventually get an address conflict.

### Start the cluster

```bash
sudo -E OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up --provider=qemu
```

Two things about that command:

- `sudo` is required because macOS's `vmnet` framework (which provides bridged
  networking) needs elevated privileges.
- `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` works around a crash where the Objective-C
  runtime — pulled in by `vmnet` — refuses to continue after QEMU's `-daemonize` calls
  `fork()`.

Override the network per-run if you need to:

```bash
LAN_PREFIX=192.168.1 VAGRANT_BRIDGE=en1 sudo -E OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up --provider=qemu
```

### VM layout

All four machines are bridged onto the LAN, so these addresses answer from any device on
the router — not just from the host.

| VM | Containers | IP | SSH port |
|---|---|---|---|
| `postgres` | postgres, redis, rabbitmq | `<prefix>.50` | 2222 |
| `history` | history-service | `<prefix>.51` | 2223 |
| `backend` | backend-service | `<prefix>.52` | 2224 |
| `ui` | ui-service | `<prefix>.53` | 2225 |
| `fetcher` | fetcher-service | `<prefix>.54` | 2226 |

Open the dashboard at `http://<prefix>.53` — including from your phone.

### Everyday commands

```bash
sudo -E vagrant status
sudo -E vagrant ssh backend -- 'docker ps'
sudo -E vagrant ssh history -- 'docker logs history --tail 20'
sudo -E vagrant provision ui        # rebuild one service after a push
sudo -E vagrant destroy -f
```

`sudo` is needed for these too: the QEMU processes belong to root, so an unprivileged
`vagrant` cannot even read their state.

### Adding another VM

Every machine is generated from one dictionary, so adding a service means adding an entry
to `NODES` in the `Vagrantfile` — a new octet, an SSH port, and the `docker run` line.
The `fetcher` VM was added exactly that way: one entry, no new config block.

> The provisioner clones this repo from GitHub (`REPO_BRANCH`), not from your working
> copy. Push your changes before running `vagrant provision`, or the VMs will rebuild the
> old code.

## Running locally with Docker Compose

A single-host equivalent of the same topology, useful for quick iteration:

```bash
docker-compose up --build -d   # dashboard on http://localhost:8080
docker-compose down -v
```

## Key endpoints

Prepend `http://<prefix>.52:8000` for a direct backend call, or `http://<prefix>.53/api`
to go through the UI's nginx proxy (it strips the `/api/` prefix before forwarding).

**Fetcher** (`http://<prefix>.54:8002`)

- `GET /health` — what the fetcher has been doing: sweep count, last sweep time,
  cities seen. Observability only; it never triggers a fetch.

**Sessions**

- `GET /session` — bootstrap: ensures a session cookie and returns its saved UI state
- `GET /session/state` — read the stored preferences
- `PUT /session/state` — merge a patch into them
- `DELETE /session` — drop the state and issue a fresh session

**Cities and readings**

- `GET /geocode?q=<city>` — proxied geocoding lookup
- `POST /cities?city=<city>` — start watching a city (registration only, no weather fetch)
- `DELETE /cities?city=<city>` — stop watching it
- `GET /cities` — list the watch pool
- `GET /latest?city=<city>` — last stored reading, from cache or the history DB

**History**

- `GET /history/recent?limit=<n>&offset=<n>` — paged history, newest first
- `GET /history/count` — total row count
- `DELETE /history/clear` — wipe the log
- `DELETE /history/{id}` — delete one row

## Verifying the stack

End-to-end proof that the async path works:

```bash
curl -s http://<prefix>.52:8000/history/count
curl -s -X POST "http://<prefix>.52:8000/cities?city=Odesa"
sleep 5
curl -s http://<prefix>.52:8000/history/count     # should have grown by one
```

The count grows only if the backend published to RabbitMQ, History consumed the message,
and PostgreSQL accepted the insert.

RabbitMQ management UI at `http://<prefix>.50:15672` (`app` / `example`). Under
**Queues → weather.events** you should see `Consumers: 1` — that is the history service.

Resilience demo — the message survives a dead consumer:

```bash
sudo -E vagrant ssh history -- 'docker stop history'
curl -s -X POST "http://<prefix>.52:8000/cities?city=Poltava"
# management UI now shows Ready: 1, Consumers: 0 — the message is waiting
sudo -E vagrant ssh history -- 'docker start history'
sleep 5
curl -s "http://<prefix>.52:8000/history/recent?limit=1"   # Poltava is there
```

## Environment variables

| Variable | Service | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | history | set by Vagrant/compose | PostgreSQL connection string |
| `RABBITMQ_URL` | history, fetcher | set by Vagrant/compose | AMQP broker URL |
| `WEATHER_EVENTS_QUEUE` | history, fetcher | `weather.events` | Queue name for the write path |
| `HISTORY_BASE` | backend | `http://history:8001` | Where the backend sends its HTTP reads |
| `REDIS_URL` | backend | `redis://postgres:6379/0` | Session store |
| `SESSION_TTL_SECONDS` | backend | `2592000` (30 days) | Sliding session lifetime |
| `POLL_INTERVAL_SECONDS` | fetcher | `1800` | How often the fetcher sweeps the watch list |
| `MIN_RECORD_INTERVAL_SECONDS` | fetcher | `600` | Minimum gap between two stored readings for one city |
| `WATCHED_CITIES` | backend | `Kyiv,Lviv` | Cities seeded into the list on first boot only |
| `BACKEND_HOST` | ui | `backend` | Rendered into `nginx.conf` at container start via `envsubst` |

## Database inspection

```bash
psql -h <prefix>.50 -U postgres -d history_db -W    # password: example
```

```sql
SELECT id, event_time, query_params->>'city' AS city, response_status
FROM requests_history ORDER BY id DESC LIMIT 10;
```

## Notes

- Credentials here (`example`, `app`/`example`) are for local learning only — do not
  reuse them anywhere.
- `history-service` still exposes `POST /history/events`. The backend no longer uses it;
  it is kept for manually injecting a test event without a broker running.
- The `ui-service` image renders `nginx.conf` from a template at startup, so the same
  image works under Compose (DNS name `backend`) and under Vagrant (a LAN IP).