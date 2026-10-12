# DatabaseInstanceDown

**Severity:** critical

## What it means

A PostgreSQL instance of the CloudNativePG cluster `oilscope-db` is not
answering. If it was the primary, CloudNativePG promotes the replica and the
`oilscope-db-rw` service follows it; until a new replica catches up there is
no second copy to fail over to.

## Check

```bash
kubectl -n oilscope get cluster oilscope-db                # PRIMARY, READY, STATUS
kubectl -n oilscope get pods -l cnpg.io/cluster=oilscope-db -o wide
kubectl -n oilscope describe pod <instance>               # Events: PVC, node, OOMKilled
kubectl -n oilscope logs <instance> --previous | tail -50
kubectl -n oilscope get pvc
```

With the `cnpg` kubectl plugin: `kubectl cnpg status oilscope-db -n oilscope`.

## Mitigate

- The pod is stuck on a lost node: once the node is gone for good,
  `kubectl -n oilscope delete pod <instance>`; CloudNativePG recreates it.
- The volume is full: expand `storage` in the cluster spec, or follow
  [node-disk-almost-full.md](node-disk-almost-full.md) when the node disk
  is the problem.
- Both instances down: the application is down too. Restore the service
  first, then the data — never delete a PVC of the last instance.

## Escalate

Both instances down, or a failover did not happen within five minutes: page
the second line immediately.
