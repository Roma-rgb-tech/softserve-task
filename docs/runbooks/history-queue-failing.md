# HistoryQueueMessagesFailing

**Severity:** warning

## What it means

`history` failed to store messages from the PGMQ queue in the last 15
minutes. `failed` messages come back and are retried; `dropped` ones went
past `PGMQ_MAX_ATTEMPTS` and their price observations are lost.

## Check

```bash
kubectl -n oilscope logs deploy/history --since=30m | grep -iE 'failed|dropped|error' | tail -30
kubectl -n oilscope get cluster oilscope-db
```

Queue depth:

```bash
kubectl -n oilscope exec -it oilscope-db-1 -- psql -U postgres -d oil_tracker -c \
  "SELECT queue_name, queue_length, oldest_msg_age_sec FROM pgmq.metrics_all();"
```

## Mitigate

- The database is degraded: see
  [database-instance-down.md](database-instance-down.md).
- `invalid` messages are a contract mismatch between `fetcher` and
  `history` — usually a release of one without the other; roll back the
  newer one.

## Escalate

`dropped` keeps growing: data is being lost — page the second line.
