# Alerting in the cluster

The clouds' own monitoring ([monitoring.md](monitoring.md)) watches VMs. On a
cluster — k3s or managed — the workloads are pods, and the signals that
matter are in Prometheus: a service that stopped answering, a burst of 5xx, a
database instance gone, a node out of CPU. This page is how those become a
page on someone's phone.

```text
 Prometheus ── evaluates PrometheusRules every 30s
     │  firing alerts
     ▼
 Alertmanager ── groups by alertname/namespace/severity, inhibits duplicates
     │  severity=critical|warning            severity=info, Watchdog
     ▼                                        ▼
 PagerDuty (Events API v2)                  "null" (visible on the
     │  escalation policy, urgency            Alertmanager page only)
     ▼
 the person on call: push, SMS, phone call ── Acknowledge ── Resolve
```

Alertmanager always runs. Without a PagerDuty routing key it routes
everything to `null`: the alerts are visible at
`http://alertmanager.<internal domain>` and nobody is woken up. With the key
it pages.

## What is watched

The chart's default rules cover Kubernetes itself — `KubePodCrashLooping`,
`KubeNodeNotReady`, `KubePersistentVolumeFillingUp`, `TargetDown` and the
rest. On top of them:

| Alert | Condition | Severity | Defined in |
| --- | --- | --- | --- |
| OilscopeServiceDown | `up == 0` for `ui`, `history` or `fetcher`, 2 min | critical | `cluster_app/templates/alerts.yaml.j2` |
| OilscopeServiceMissing | no scrape target for one of them, 5 min | critical | same |
| OilscopeHighErrorRate | 5xx > 5% of requests and ≥ 5 errors, 5 min | critical | same |
| OilscopeSlowResponses | p95 response time > 1 s, 10 min | warning | same |
| FetcherStale | no successful collection for 7 h | warning | same |
| HistoryQueueMessagesFailing | failed or dropped queue messages in 15 min | warning | same |
| DatabaseInstanceDown | a CloudNativePG instance down, 2 min | critical | same |
| DatabaseReplicationLag | replica > 30 s behind, 5 min | warning | same |
| NodeHighCPU | node CPU > `monitoring.cpu_percent` (warning) / 95% (critical), 5 min | warning, critical | `cluster_platform/templates/platform-rules.yaml.j2` |
| NodeHighMemory | node memory > `monitoring.memory_percent`, 10 min | warning | same |
| NodeDiskAlmostFull | filesystem > `monitoring.disk_percent`, 10 min | warning | same |

The node thresholds come from the same `monitoring` block of the project
configuration as the cloud alerts, so 80% means the same thing for a VM and
for a node. Every rule carries a `runbook_url` into
[runbooks/](runbooks/README.md), and PagerDuty shows it as a link on the
incident.

### Why these numbers

- **A window, not a single sample.** CPU over 80% for one scrape is a
  deploy or a cron job; for five minutes it is load. Paging on spikes trains
  people to ignore the pager.
- **Error rate, not error count — with a floor.** 5% of the traffic says
  users are affected; the "at least five errors" floor stops one failed
  request on an idle stand from reading as 100%.
- **Critical pages, warning informs.** A critical means "someone has to act
  now" (the site or the database is down). A warning means "act today".
  PagerDuty's urgency rules turn the first into a phone call and the second
  into a low-urgency incident.
- **A critical silences its own warning.** `NodeHighCPU` at 97% fires both
  rules; the inhibit rule keeps only the critical.

## Routing

`cluster_platform/files/values/kube-prometheus-stack.yaml` holds the base
configuration — receivers, grouping, inhibition — and
`kube-prometheus-stack-pagerduty.yaml` adds the paging route. The role adds
the second file only when the routing key is set.

| Matcher | Receiver |
| --- | --- |
| `alertname =~ Watchdog\|InfoInhibitor` | null — Watchdog fires all the time on purpose |
| `severity =~ info\|none` | null |
| `severity =~ critical\|warning` | pagerduty |

Alerts are grouped by `alertname`, `namespace` and `severity`: twenty
crash-looping pods of one Deployment are one incident, not twenty. A group
repeats every four hours while it keeps firing, and PagerDuty resolves the
incident by itself when Alertmanager sends the resolution.

## Turning paging on

1. **PagerDuty** (the free plan is enough):
   - create a **Service**, for example `oilscope-prod`, with an
     **Escalation Policy** (you first, someone else after 5 minutes without
     an acknowledgement);
   - on the service, **Integrations → Add an integration → Events API V2**,
     and copy the **Integration Key**. That is the routing key;
   - optionally, **Urgency → Based on alert severity**, so warnings do not
     ring the phone;
   - install the PagerDuty app and allow its notifications.

2. **Map the key** in the `secret_mappings` of the first k3s server — the
   entry that also feeds a managed cluster:

   ```json
   "PAGERDUTY_ROUTING_KEY": "oilscope-prod-pagerduty-routing-key"
   ```

   It is a platform secret like the Cloudflare token and the Grafana
   password: Ansible reads it and writes it into the cluster. External
   Secrets keeps reading only the four application secrets.

3. **Create the container and fill it.** `terraform apply` creates the empty
   container in the secret store and grants read access; then

   ```bash
    read -rs PAGERDUTY_ROUTING_KEY && export PAGERDUTY_ROUTING_KEY
   ansible-playbook oilscope.platform.upload_secret_versions \
     -e secret_versions_config_file=~/configs/oilscope/oilscope.json
   unset PAGERDUTY_ROUTING_KEY
   ```

   `read -s` keeps the key off the screen and out of the shell history.

4. **Deploy** — `site.yml` or `cluster.yml` as usual. The role writes the key
   into the `alertmanager-pagerduty` Secret in `monitoring`, the operator
   mounts it into Alertmanager, and Alertmanager reads it from the file
   (`routing_key_file`), so the key never appears in the Helm values or in
   the release history.

Removing the mapping and running the playbook again returns Alertmanager to
`null`.

## Testing it

**The pipeline, without breaking anything.** Send a synthetic alert
straight to Alertmanager:

```bash
kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  amtool alert add TestPage severity=critical namespace=oilscope \
  --annotation='summary="Test page from the OilScope Alertmanager"' \
  --annotation='runbook_url="https://github.com/ua-academy-projects/push-and-pray/blob/main/docs/runbooks/README.md"' \
  --alertmanager.url=http://localhost:9093
```

PagerDuty opens an incident within a minute (the group wait is 30 s). The
alert resolves by itself after five minutes, and so does the incident.

**A real rule, end to end.** Load one node until `NodeHighCPU` fires:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
for i in 1 2; do
  kubectl run cpu-burn-$i --image=busybox --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$NODE\"}}" -- sh -c 'while :; do :; done'
done
# about ten minutes later: Prometheus → Alerts shows it firing, PagerDuty pages
kubectl delete pod cpu-burn-1 cpu-burn-2
```

Use one `cpu-burn` pod per vCPU of the node; two fill a two-vCPU node. The
`for` duration plus the five-minute rate window is why it takes about ten
minutes to fire — and about as long to resolve.

**Check the configuration Alertmanager actually loaded:**

```bash
kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  amtool config routes test --alertmanager.url=http://localhost:9093 severity=critical alertname=X
```

## Silences and maintenance

Planned work that will trip alerts — a node upgrade, a database restore —
gets a silence first, on the Alertmanager page (**New Silence**) or:

```bash
kubectl -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  amtool silence add namespace=oilscope --duration=1h --comment="node pool upgrade" \
  --alertmanager.url=http://localhost:9093
```

A silence has an end time, so a forgotten one expires instead of hiding the
next real outage.
