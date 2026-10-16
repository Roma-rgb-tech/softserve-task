# LogStoreUnavailable, LogPipelineUnavailable, LogShipperMissing

## What it means

A part of the log pipeline (see [../logging.md](../logging.md)) has not been
running for 10-15 minutes:

- **LogStoreUnavailable** - Elasticsearch is not ready. Nothing new is stored;
  Kibana shows old lines or errors.
- **LogPipelineUnavailable** - Logstash is not ready. Filebeat keeps retrying
  and nothing reaches Elasticsearch.
- **LogShipperMissing** - a node has no running Filebeat; its pods' logs are not
  collected.

The application itself is not affected. What is at risk is the next incident:
logs that are not collected now cannot be searched later. Severity warning,
working hours.

## Check

```bash
kubectl -n logging get elasticsearch,kibana,logstash,beat      # HEALTH and PHASE columns
kubectl -n logging get pods -o wide
kubectl -n logging describe pod logs-es-default-0              # Events: Pending? OOMKilled?
kubectl -n logging logs logs-es-default-0 --tail=100
kubectl -n logging logs logs-ls-0 --tail=100                   # connection errors to Elasticsearch?
kubectl -n logging logs ds/logs-beat-filebeat --tail=50        # "Failed to connect to backoff(async(tcp://logs-ls-beats..."
kubectl -n elastic-system logs statefulset/elastic-operator --tail=50
kubectl -n logging get pvc                                     # Elasticsearch volume full or unbound?
kubectl top pods -n logging ; kubectl top nodes                # memory pressure
```

Typical causes:

- **Pending** - not enough memory on any node (Elasticsearch requests 2 GB).
- **OOMKilled** - the limit is too low for the load; Logstash's heap is set by
  `LS_JAVA_OPTS`.
- **Disk** - the Elasticsearch volume is full: retention too long for the
  volume, or a noisy pod. Elasticsearch blocks writes at the flood-stage
  watermark (95%).
- **Filebeat missing on one node** - the node is NotReady, or a taint the
  DaemonSet does not tolerate.

## Mitigate

- Memory: add a node or raise the node size; as a stopgap, scale Kibana to 0
  (`kubectl -n logging patch kibana logs --type merge -p '{"spec":{"count":0}}'`).
- Disk: lower `retention_days` and run the playbook (the template Job applies
  the new lifecycle), or raise `storage_gb` - ECK expands the volume where the
  StorageClass allows it.
- A stuck pod: `kubectl -n logging delete pod <pod>`; ECK recreates it.

## Escalate

If Elasticsearch stays red after a restart, or its volume is lost, escalate
to the platform owner before deleting anything - deleting the PVC deletes the
stored logs.
