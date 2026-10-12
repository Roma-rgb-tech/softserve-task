# NodeHighMemory

**Severity:** warning

## What it means

Less memory than the `monitoring.memory_percent` threshold allows (85% used
by default) has been available on a node for ten minutes. Next come pod
evictions and OOM kills.

## Check

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -15
kubectl describe node <node> | grep -A5 Conditions        # MemoryPressure?
kubectl get pods -A | grep -iE 'evicted|oomkilled'
```

## Mitigate

- One pod grows without bound (a leak): restart it now, open a ticket for
  the developers with the graph.
- Requests are too low, so the scheduler packs too much on one node: raise
  the memory requests in the Helm values.
- Not enough nodes: add one (`kubernetes.node_count`).

## Escalate

Pods are being evicted from several nodes: page the second line.
