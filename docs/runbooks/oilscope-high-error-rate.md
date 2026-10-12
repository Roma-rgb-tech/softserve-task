# OilscopeHighErrorRate

**Severity:** critical

## What it means

More than 5% of the requests to `ui` or `history`, and at least five of them,
ended in a 5xx over the last five minutes. Users see errors.

## Check

```bash
kubectl -n oilscope logs deploy/<job> --since=15m | grep -iE 'error|exception|traceback' | tail -50
kubectl -n oilscope get pods                        # restarts?
kubectl -n oilscope get cluster oilscope-db         # CloudNativePG: is the database healthy?
kubectl -n oilscope get events --sort-by=.lastTimestamp | tail -20
```

In Prometheus, which route fails:

```promql
sum by (handler) (rate(http_requests_total{namespace="oilscope", job="<job>", status="5xx"}[5m]))
```

Then ask what changed: the last image tag commit in Git, the last Argo CD
sync, a Key Vault secret rotation.

## Mitigate

- Started with a release: roll it back (revert the tag commit, or
  `argocd app rollback oilscope`).
- The database or Redis is unreachable: follow
  [database-instance-down.md](database-instance-down.md); check
  `kubectl -n oilscope get pods | grep -i redis`.
- `history` fails and `ui` fails with it: `ui` calls `history`; fix
  `history` first.

## Escalate

Errors above 50%, or no candidate cause within 15 minutes: page the second
line and tell the stakeholders the site is degraded.
