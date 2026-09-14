# UI sessions

The UI keeps each visitor's chart preferences - the selected series, the range,
the metric, the layout - server side, behind a session cookie that holds nothing
but an opaque identifier. One block in the project configuration decides where
those preferences live:

```json
"sessions": {
  "backend": "redis",
  "password_secret": "oilscope-prod-redis-password"
}
```

Leave the block out and the backend is `postgresql`: the preferences go into the
`ui_sessions` table of the application database, as an `hstore` column, and a
`pg_cron` job deletes the expired rows. That works on a container, on Cloud SQL
and on RDS, because all three offer `hstore`, `pgcrypto` and `pg_cron`.

Set the backend to `redis` and the VM with role `database` gains a Redis
container, and the UI stores the same preferences there under a key with a
matching lifetime. Nothing else about the deployment changes.

## Why there is a choice at all

Sessions are the one write the UI makes on every page view, and they are the one
write nobody would miss after a restart. Keeping them in the application
database is the simpler deployment - one fewer service to run, back up and
patch. Keeping them in Redis takes that traffic off a database that is now
metered and billed by the cloud, and lets it expire keys itself instead of
running a cron job to delete rows.

Neither is right for every stand, which is why it is a configuration value and
not a decision baked into the image.

## What the switch touches

The UI service picks its store at startup from `SESSION_BACKEND`, so the same
image serves both. `RedisSessionStore` and `PostgreSQLSessionStore` implement
the same three methods, and `/health` reports which one answered:

```json
{"status": "ok", "history": "connected", "sessions": "redis"}
```

Ansible starts the Redis container only when the backend is `redis`, from a
Compose project of its own under `/opt/oilscope/cache`, so it is independent of
whichever database Compose file the machine already runs. Terraform opens port
`service_ports.redis` from the UI security group to the infrastructure machine
only in the same case - on GCP as a firewall rule, on AWS as a security group
rule - and the port stays closed otherwise.

## The password

Redis is reachable from the workload subnet, so it requires one. The value is
never in the configuration: `password_secret` names a container, the deployment
generates a value into it on the first run if it is empty, and both the
infrastructure machine and the UI read it from the cloud's own secret store at
deploy time. It reaches Redis as a command-line argument inside the container
and the UI as part of a URL that is assembled on the host, never written to a
file and never printed.

## The session identifier is never stored

Both stores hash the identifier before it touches storage - `digest(..., 'sha256')`
in PostgreSQL, `hashlib.sha256` in the Redis key - so a dump of either one
cannot be replayed as a set of cookies.

## Switching

Change `backend`, run Terraform so the port opens or closes, then run the
playbook. Sessions do not migrate: a visitor whose preferences were in the old
store starts from the defaults once. The cookie itself stays valid, so nobody is
logged out - there is nothing to log out of.
