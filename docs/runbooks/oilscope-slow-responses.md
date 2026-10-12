# OilscopeSlowResponses

**Severity:** warning

## What it means

For ten minutes, one in twenty responses of `ui` or `history` has taken more
than a second. The site works but feels slow; left alone it often turns into
timeouts (504).

## Check

```bash
kubectl top pods -n oilscope                     # CPU at the limit? throttled?
kubectl top nodes
kubectl -n oilscope get pods                     # restarts, pending replicas
```

```promql
# which route is slow
histogram_quantile(0.95, sum by (handler, le) (rate(http_request_duration_seconds_bucket{namespace="oilscope", job="<job>"}[5m])))
```

Long-running queries in PostgreSQL:

```bash
kubectl -n oilscope exec -it oilscope-db-1 -- psql -U postgres -d oil_tracker -c \
  "SELECT pid, now() - query_start AS runtime, state, left(query, 80)
   FROM pg_stat_activity WHERE state <> 'idle' ORDER BY runtime DESC LIMIT 10;"
```

## Mitigate

- CPU-bound: raise `replicas` or the CPU request in the Helm values (through
  Git).
- A slow query: find it above; an index or a smaller time range in the
  request is the usual fix, and that is a change for the developers.
- A noisy neighbour on the node: see [node-high-cpu.md](node-high-cpu.md).

## Escalate

If it turns into `OilscopeHighErrorRate`, follow that page instead.
