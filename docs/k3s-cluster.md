# The k3s cluster

The stand no longer runs the services as Docker Compose projects on one VM per
service. Terraform creates a bastion per cloud and a set of k3s nodes; Ansible
builds a k3s cluster on the nodes and installs everything else into it from the
controller with Helm and the Kubernetes API. The Compose deployment is kept at
the `snapshot/vm-compose` tag.

```
                    internet
                       │ 80/443 (any node with a public IP)
         ┌─────────────▼──────────────┐
         │ Traefik DaemonSet          │   cert-manager ── Let's Encrypt (DNS-01, Cloudflare)
         │  └─ Ingress ui ─► ui ──────┼─► history ─┐
         │                            │   fetcher ─┤
         │  Redis (sessions) ◄── ui   │            ▼
         │                            │   CloudNativePG: oilscope-db (primary + replica)
         │ Headlamp, Homepage         │     PGMQ queue, pg_cron
         └────────────▲───────────────┘
                      │ private addresses only
   operator ── tailnet ── bastion (subnet router)
```

## What the configuration says

Only the bastions and the nodes are in `vms`. A node's `role` is its place in
the cluster, and Terraform copies it into the `role` label or tag of the VM,
which the inventory plugin turns into a group:

| `role` | Group | Runs |
| --- | --- | --- |
| `k3s_server` | `k3s_server` | API server, etcd, and workloads |
| `k3s_agent` | `k3s_agent` | workloads only |

Keep one or three servers. etcd needs a majority to elect a leader; with two,
losing the link between them stops both. `assign_public_ip` may be set on any
node: Traefik runs on every node, so the site answers on each of them. The node
carrying `public_endpoint` is the one the DNS record points at, and its
`secret_mappings` hold every value the cluster needs.

`k3s` sets the release and extra API certificate names; `cluster` sets the
namespace, the internal domain of the operator pages and the size of the
PostgreSQL cluster. `database.managed` is `false`: PostgreSQL runs in the
cluster. See `project-config.example.json`.

## Reaching the cluster

The API server and the operator pages have no public address. The bastion of
each cloud is a Tailscale subnet router for that cloud's network, so the
operator joins the same tailnet and accepts its routes:

```bash
tailscale up --accept-routes
```

The kubeconfig lands in `~/.kube/<name_prefix>-<environment>.yaml` (override
with `OILSCOPE_KUBECONFIG`) and points at the first server's private address.

Headlamp and Homepage answer on plain HTTP under `cluster.internal_domain`, and
only to requests from the clouds' private ranges - which is how the tailnet
presents the operator, and never how a visitor from the internet arrives.
Point the names at any node's private address:

```
10.10.1.5  headlamp.oilscope.internal homepage.oilscope.internal
```

Headlamp asks for a token; `site.yml` prints the command that reads it.

## Running it

```bash
terraform -chdir=infrastructure/terraform apply
ansible-playbook -i infrastructure/ansible/inventory \
  oilscope.platform.site -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

The controller needs `helm` on the PATH and the Python `kubernetes` package
(`infrastructure/ansible/requirements.txt`), and the `kubernetes.core`
collection (`requirements.yml`).

`playbooks/cluster.yml` alone rebuilds the cluster layer on existing VMs. Its
plays run in order: the first server (it initialises etcd), the other servers
one at a time, the agents, then everything in the cluster from the controller.

## What is where

| Piece | Installed by | Notes |
| --- | --- | --- |
| k3s | `k3s` role | Release binary checked against its SHA-256, no install script. Bundled Traefik disabled. |
| Traefik | Helm, `cluster_platform` | DaemonSet behind ServiceLB with `externalTrafficPolicy: Local`. |
| cert-manager | Helm, `cluster_platform` | `ClusterIssuer letsencrypt`, DNS-01 through Cloudflare. |
| CloudNativePG operator | Helm, `cluster_platform` | |
| Headlamp | Helm, `cluster_platform` | Read-only `headlamp-operator` service account for signing in. |
| Redis | Helm, `cluster_app` | Bitnami chart with the `bitnamilegacy` image, standalone. |
| PostgreSQL | `Cluster` resource, `cluster_app` | The project's database image (PGMQ, pg_cron) through an `ImageCatalog`. Extensions and the queue are created once at bootstrap. Metrics on `oilscope-db-metrics:9187`. |
| Migrations | `Job`, `cluster_app` | One Job per image tag. |
| history, fetcher, ui | Deployments, `cluster_app` | One replica each. |
| Homepage | Manifests, `cluster_app` | Configured entirely by a ConfigMap; a status light per service. |

## Not carried over yet

- The monitoring agents (`playbooks/monitoring.yml`) still expect Docker
  containers and are not part of `site.yml`.
- Backups of the PostgreSQL cluster to a bucket.
