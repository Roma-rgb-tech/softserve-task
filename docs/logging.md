# Logs: ELK on the cluster

Metrics say *that* something is wrong; logs say *what*. With
`cluster.logging.enabled` the platform collects the stdout and stderr of every
pod into Elasticsearch, and Kibana searches them - next to Grafana, behind the
same tailnet-only allow list.

```
 every node                      logging namespace                          operator
┌──────────────┐  beats :5044  ┌──────────┐  https :9200  ┌───────────────┐  tailnet  ┌────────┐
│ Filebeat     │ ────────────► │ Logstash │ ────────────► │ Elasticsearch │ ◄──────── │ Kibana │ ◄── kibana.oilscope.internal
│ (DaemonSet)  │               │  grok    │               │ logs-oilscope │           └────────┘
│ /var/log/    │               │  fields  │               │   -default    │
│  containers  │               └──────────┘               └───────────────┘
└──────────────┘                                           retention_days, then deleted
```

All four come from one operator, **ECK** (Elastic Cloud on Kubernetes),
installed with Helm by the `cluster_platform` role. ECK turns four small
resources - `Elasticsearch`, `Kibana`, `Logstash` and `Beat` - into the
StatefulSets, DaemonSet, Services, certificates and passwords they need.

## Turning it on

```json
"cluster": {
  "logging": {
    "enabled": true,
    "storage_gb": 10,
    "retention_days": 7
  }
}
```

Then run the cluster layer again (`playbooks/cluster.yml` or `site.yml`). It is
off by default for a reason: Elasticsearch asks for 2 GB of memory, Logstash
and Kibana for about 1 GB each. Three `medium` nodes (4 GB) already carry
Prometheus, Grafana and the database; give the cluster a fourth node or
`large` nodes before turning logs on.

## What each piece does

| Piece | Resource | Notes |
| --- | --- | --- |
| ECK operator | Helm `eck-operator`, namespace `elastic-system` | Reconciles the four resources below; installs their CRDs. |
| Filebeat | `Beat logs` → DaemonSet `logs-beat-filebeat` | Autodiscover reads `/var/log/containers/*.log` on its node, adds pod, namespace, labels and node. The `logging` namespace is dropped so the stack does not log itself. |
| Logstash | `Logstash logs` → StatefulSet `logs-ls`, Service `logs-ls-beats:5044` | Parses the OilScope services' lines (below) and writes the data stream. ECK hands it the address, a user and the CA of Elasticsearch as `LOGS_ES_*`. |
| Elasticsearch | `Elasticsearch logs` → StatefulSet `logs-es-default` | One node, TLS and a generated `elastic` password. `node.store.allow_mmap: false`, so no privileged init container. |
| Kibana | `Kibana logs` → `logs-kb-http:5601` | Plain HTTP behind Traefik's `internal-only` middleware, like Grafana. |
| Retention | Job `logs-index-template-<hash>` | Puts the `logs-oilscope` index template **before** the first line arrives: a data stream lifecycle that deletes lines older than `retention_days`, one shard, no replica, keyword fields. |

## Fields Logstash adds

Lines from the application namespace are matched against the three formats
the services write:

| Service | Format | Fields |
| --- | --- | --- |
| history, ui | Python logging - `2026-10-16 08:12:33,123 INFO history_service.main …` | `log.level`, `log.logger`, `message` |
| history, ui | uvicorn access - `INFO: 10.42.0.7:51334 - "GET /health HTTP/1.1" 200 OK` | `client.ip`, `http.request.method`, `url.path`, `http.response.status_code`; tag `http_5xx` for 500+ |
| fetcher | Go `log/slog` - `2026/10/16 08:12:33 ERROR invalid configuration …` | `log.level`, `message` |

Every line also has `service.name` (the container) and the Kubernetes metadata
Filebeat added. A line that matches none of them - a Python traceback, for
one - keeps its text and gets the tag `_unparsed`.

## Signing in

The playbook prints it at the end:

```bash
open http://kibana.oilscope.internal          # over the tailnet
kubectl -n logging get secret logs-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d
```

User `elastic`. Once, create the data view: **Stack Management → Data views →
Create**, name `OilScope`, index pattern `logs-oilscope-*`, timestamp
`@timestamp`. Then **Discover**.

Useful queries (KQL):

```
service.name : "history" and log.level : "error"
tags : "http_5xx"
http.response.status_code >= 500 and url.path : "/api/*"
kubernetes.namespace : "oilscope" and tags : "_unparsed"
```

## During an incident

The alert and the runbook say *where* to look; the logs say *what happened*.
A typical path for `OilscopeHighErrorRate`:

1. Kibana → Discover, last 15 minutes, `tags : "http_5xx"` - which paths fail.
2. Same window, `service.name : "history" and log.level : "error"` - the
   exception behind them.
3. `kubernetes.pod.name` in the results - one pod or all of them? One pod
   points at that pod (restart it); all of them point at a dependency or the
   last deploy (roll back).

## Watching the pipeline itself

`templates/logging-rules.yaml.j2` adds three alerts on kube-state-metrics,
routed like the rest through Alertmanager:

| Alert | When |
| --- | --- |
| LogStoreUnavailable | Elasticsearch not ready for 10 minutes |
| LogPipelineUnavailable | Logstash not ready for 10 minutes |
| LogShipperMissing | Filebeat missing from a node for 15 minutes |

See [runbooks/logging-pipeline.md](runbooks/logging-pipeline.md).

## Why ELK and not only Loki

Both answer "what did the pods print". Loki indexes only the labels and is
cheap; Elasticsearch indexes every word, so a free-text search over days of
logs is fast, and Kibana's Discover is the tool many operations teams already
use. Here it also shows the full pipeline - shipper, parser, store, UI - that
the ELK name stands for.

## Turning it off

Set `enabled` to false and remove what the playbook created:

```bash
kubectl delete namespace logging            # Elasticsearch volume included
helm uninstall eck-operator -n elastic-system
kubectl delete clusterrole,clusterrolebinding filebeat
kubectl -n monitoring delete prometheusrule oilscope-logging
```
