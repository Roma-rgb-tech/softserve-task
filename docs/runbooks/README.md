# Runbooks

One page per alert. Every rule's `runbook_url` points here, and the link
arrives with the PagerDuty incident, so whoever is on call starts from the
page rather than from a blank terminal.

Each page has the same four parts:

1. **What it means** — the condition in plain words and who notices it.
2. **Check** — commands in the order worth running them.
3. **Mitigate** — what restores the service now. Restore first, root cause
   second.
4. **Escalate** — when to stop and wake someone else.

| Alert | Severity | Page |
| --- | --- | --- |
| OilscopeServiceDown, OilscopeServiceMissing | critical | [oilscope-service-down.md](oilscope-service-down.md) |
| OilscopeHighErrorRate | critical | [oilscope-high-error-rate.md](oilscope-high-error-rate.md) |
| OilscopeSlowResponses | warning | [oilscope-slow-responses.md](oilscope-slow-responses.md) |
| FetcherStale | warning | [fetcher-stale.md](fetcher-stale.md) |
| HistoryQueueMessagesFailing | warning | [history-queue-failing.md](history-queue-failing.md) |
| DatabaseInstanceDown | critical | [database-instance-down.md](database-instance-down.md) |
| DatabaseReplicationLag | warning | [database-replication-lag.md](database-replication-lag.md) |
| NodeHighCPU | warning, critical | [node-high-cpu.md](node-high-cpu.md) |
| NodeHighMemory | warning | [node-high-memory.md](node-high-memory.md) |
| NodeDiskAlmostFull | warning | [node-disk-almost-full.md](node-disk-almost-full.md) |

The chart's own rules (`KubePodCrashLooping`, `KubeNodeNotReady`,
`KubePersistentVolumeFillingUp`, `TargetDown` …) link to the upstream
runbooks at runbooks.prometheus-operator.dev.

Every page assumes the stand's kubeconfig is the current context
(`oilscope.platform.kube_context` makes it so) and uses `oilscope` as the
application namespace.

After an incident, write down what happened — timeline, impact, root cause,
what changes so it does not repeat — and fix this page if it sent you the
wrong way.
