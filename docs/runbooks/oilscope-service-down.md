# OilscopeServiceDown / OilscopeServiceMissing

**Severity:** critical

## What it means

`ui`, `history` or `fetcher` has stopped answering Prometheus for two minutes
(`ServiceDown`), or there is no pod of it to ask at all for five
(`ServiceMissing`). For `ui` the site is down; for `history` the charts are
empty; for `fetcher` no new prices arrive.

## Check

```bash
kubectl -n oilscope get pods -o wide
kubectl -n oilscope describe pod <pod>          # Events: OOMKilled, probes, image pull
kubectl -n oilscope logs <pod> --previous       # why the last container died
kubectl -n oilscope get deploy                  # READY 0/1? replicas 0?
kubectl get applications -n argocd              # is Argo CD in sync, or mid-rollout?
```

Typical causes, by the pod's state:

| State | Usual cause |
| --- | --- |
| `CrashLoopBackOff` | the application exits: bad configuration, the database unreachable — read `logs --previous` |
| `ImagePullBackOff` | the tag does not exist or the registry token expired (`describe` shows 401/403) |
| `OOMKilled` | the memory limit in `deploy/helm/oilscope/values.yaml` is too low for the load |
| `Pending` | no node has room: `kubectl describe pod` shows the scheduler's reason |
| no pod at all | replicas 0, or the Deployment was removed — compare with Git |

## Mitigate

- A bad release: roll back in Git (revert the image tag commit) and let Argo
  CD sync, or `argocd app rollback oilscope` for the immediate fix.
- An expired registry token: update `GHCR_TOKEN` in Key Vault; External
  Secrets copies it within the refresh interval, then delete the stuck pod.
- A stuck pod: `kubectl -n oilscope delete pod <pod>` — the Deployment
  recreates it.

## Escalate

If the cause is not clear within 15 minutes, or the database is also down
(see [database-instance-down.md](database-instance-down.md)), page the
second line.
