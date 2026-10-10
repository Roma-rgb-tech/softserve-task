# cluster_platform

The layer every application on the cluster relies on, installed from the
controller as Helm releases, each with a short values file in `files/values`:

| Release | Namespace | What it adds |
| --- | --- | --- |
| traefik | traefik | Ingress on every node (DaemonSet), default IngressClass |
| cert-manager | cert-manager | `ClusterIssuer letsencrypt`, DNS-01 through Cloudflare |
| cnpg | cnpg-system | The CloudNativePG operator |
| kube-prometheus-stack | monitoring | Prometheus, Grafana, node-exporter, kube-state-metrics; reachable only from the private ranges |
| headlamp | headlamp | Dashboard, reachable only from the private ranges |
| argocd | argocd | Argo CD, only when `kubernetes.gitops.enabled` is true; reachable only from the private ranges |

Chart versions are Helm constraints in `cluster_platform_charts`, so patch
releases arrive on their own and a new major waits for a deliberate change.

Headlamp's sign-in token belongs to the `headlamp-operator` service account,
which may read every resource and change none.
