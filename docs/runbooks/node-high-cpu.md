# NodeHighCPU

**Severity:** warning above the `monitoring.cpu_percent` threshold (80% by
default), critical above 95%. Both mean the five-minute average CPU of one
node has stayed over the line for five minutes.

## What it means

The node is busy enough that its pods compete for CPU. At the critical level
the containers with CPU limits are throttled and responses slow down.

## Check

```bash
kubectl top nodes
kubectl top pods -A --sort-by=cpu | head -15          # who is using it
kubectl describe node <node> | sed -n '/Allocated resources/,/Events/p'
kubectl get events -A --sort-by=.lastTimestamp | tail -20
```

Ask whether it is expected: a release rolling out, the database restoring,
a load test. Compare with the CPU graph in Grafana over the last day.

## Mitigate

- A runaway pod: delete it, or roll back the release that brought it.
- Real load: more replicas spread over the nodes, or a larger
  `kubernetes.node_count` / `node_size` in the project configuration and a
  `terraform apply`.

## Escalate

Critical for more than 15 minutes with users affected
([oilscope-slow-responses.md](oilscope-slow-responses.md)): page the second
line.
