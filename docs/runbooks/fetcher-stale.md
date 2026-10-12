# FetcherStale

**Severity:** warning

## What it means

The fetcher collects prices at 00, 06, 12 and 18 UTC. Its last successful
collection is more than seven hours old, so at least one was missed. The
site still answers, with old prices.

## Check

```bash
kubectl -n oilscope logs deploy/fetcher --since=8h | tail -50
kubectl -n oilscope get pods -l app.kubernetes.io/name=fetcher
```

```promql
fetcher_collections_total{namespace="oilscope"}      # failure vs success
```

Typical causes: the OilPriceAPI key expired or hit its quota (401/429 in the
logs), the API is down, the queue in PostgreSQL is unreachable.

## Mitigate

- An expired key: put the new value into the `OILPRICEAPI_KEY` secret in Key
  Vault (`upload_secret_versions`), wait for External Secrets, then
  `kubectl -n oilscope rollout restart deploy/fetcher` — it collects on
  start-up.
- The provider is down: nothing to fix on our side; note it in the incident
  and wait for the next scheduled run.

## Escalate

Not a night-time page. Hand over to the day shift if it is still firing in
the morning.
