# cluster_app

OilScope inside the cluster, applied from the controller:

1. Secrets built from the values the first k3s server resolved: the registry
   credentials, the database role, the Redis password and the services'
   connection strings. Nothing is written to disk.
2. Redis from the Bitnami chart, for the UI sessions.
3. A CloudNativePG `Cluster` running the project's own database image through
   an `ImageCatalog`. PGMQ, pg_cron, hstore and pgcrypto, the queue and the
   grants the application role needs are created once, at bootstrap, by the
   superuser.
4. The migrations, as one Job per image tag (with GitOps, a PreSync hook of
   the chart instead).
5. history, fetcher and ui, and an Ingress for the UI with a certificate from
   cert-manager, all from the Helm chart in `deploy/helm/oilscope`. Without
   GitOps the role renders the chart and applies it; with
   `kubernetes.gitops.enabled` it creates an Argo CD `Application` instead,
   and Argo CD keeps the cluster in step with the chart in Git
   (see `docs/gitops.md`).
6. Homepage, configured by a ConfigMap, with a link and a status light for
   every service. Reachable only from the private ranges.
7. ServiceMonitors for the services, a PodMonitor for the PostgreSQL
   instances, and the OilScope dashboard (`files/oilscope-dashboard.json`)
   as a ConfigMap Grafana's sidecar loads.
