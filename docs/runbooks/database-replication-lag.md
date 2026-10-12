# DatabaseReplicationLag

**Severity:** warning

## What it means

The replica has been more than 30 seconds behind the primary for five
minutes. Reads still work; a failover now would lose the transactions the
replica has not replayed yet (the RPO grows with the lag).

## Check

```bash
kubectl -n oilscope get cluster oilscope-db
kubectl -n oilscope exec -it <primary> -- psql -U postgres -c \
  "SELECT application_name, state, write_lag, replay_lag FROM pg_stat_replication;"
kubectl top pods -n oilscope -l cnpg.io/cluster=oilscope-db
```

Usual causes: a heavy write burst, the replica's node short of CPU or disk
throughput, network trouble between the zones.

## Mitigate

Usually it catches up by itself once the burst ends. If the replica is
stuck, `kubectl cnpg destroy oilscope-db <instance> -n oilscope` lets the
operator rebuild it from the primary.

## Escalate

The lag keeps growing for 30 minutes: hand over to the second line.
