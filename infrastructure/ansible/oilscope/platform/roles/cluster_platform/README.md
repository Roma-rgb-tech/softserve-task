# cluster_platform

The layer every application on the cluster relies on, installed from the
controller as Helm releases, each with a short values file in `files/values`:

| Release | Namespace | What it adds |
| --- | --- | --- |
| traefik | traefik | Ingress on every node (DaemonSet), default IngressClass |
| cert-manager | cert-manager | `ClusterIssuer letsencrypt`, DNS-01 through Cloudflare |
| cnpg | cnpg-system | The CloudNativePG operator |
| kube-prometheus-stack | monitoring | Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, and the node alert rules; reachable only from the private ranges |
| headlamp | headlamp | Dashboard, reachable only from the private ranges |
| argocd | argocd | Argo CD, only when `kubernetes.gitops.enabled` is true; reachable only from the private ranges |
| external-secrets | external-secrets | External Secrets Operator, with GitOps on AKS: copies the application secrets from Key Vault |

Chart versions are Helm constraints in `cluster_platform_charts`, so patch
releases arrive on their own and a new major waits for a deliberate change.

Headlamp's sign-in token belongs to the `headlamp-operator` service account,
which may read every resource and change none.

## Alerting

Alertmanager always runs. `cluster_platform_pagerduty_routing_key` — the
`PAGERDUTY_ROUTING_KEY` mapping of the first k3s server — decides where the
alerts go: empty, they stay on the Alertmanager page; set, the role writes it
into the `alertmanager-pagerduty` Secret and adds
`files/values/kube-prometheus-stack-pagerduty.yaml`, which routes warning and
critical alerts to PagerDuty. `templates/platform-rules.yaml.j2` adds the node
CPU, memory and disk alerts with the thresholds of the project
configuration's `monitoring` block. See [docs/alerting.md](../../../../../../docs/alerting.md).
