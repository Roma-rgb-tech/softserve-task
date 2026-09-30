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
4. The migrations, as one Job per image tag.
5. history, fetcher and ui, and an Ingress for the UI with a certificate from
   cert-manager.
6. Homepage, configured by a ConfigMap, with a link and a status light for
   every service. Reachable only from the private ranges.
