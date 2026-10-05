# Managed Kubernetes: GKE, EKS or AKS

The cluster can come from two places, chosen by one field in the project
configuration:

| `kubernetes.managed` | Cluster | Built by |
| --- | --- | --- |
| `false`, or no `kubernetes` block | k3s on the `k3s_server` / `k3s_agent` VMs | Terraform (VMs) + the `k3s` role |
| `true` | GKE, EKS or AKS, in `kubernetes.cloud` (default `default_cloud`) | Terraform (cluster) |

Everything after that is the same code: Ansible puts the cluster's credentials
in the stand's kubeconfig, makes it the operator's current context, and the
`cluster_platform` and `cluster_app` roles install Traefik, cert-manager,
CloudNativePG, kube-prometheus-stack, Headlamp, Redis, the application and
Homepage into it, exactly as on k3s. See [k3s-cluster.md](k3s-cluster.md) for
what each of those does.

```
                          internet
                             │ 80/443
                ┌────────────▼─────────────┐
                │ public load balancer      │  ◄── app.<domain> (Cloudflare, set by Ansible)
                └────────────┬─────────────┘
         ┌───────────────────▼─────────────────────────┐
         │ GKE / EKS / AKS (private nodes)              │
         │  Traefik DaemonSet ─► ui, history, fetcher   │
         │  CloudNativePG, Redis, Prometheus, Grafana,  │
         │  Headlamp, Homepage                          │
         └───────────────────▲─────────────────────────┘
                ┌────────────┴─────────────┐
                │ internal load balancer    │  ◄── *.oilscope.internal (CoreDNS on the bastion)
                └────────────▲─────────────┘
   operator ── tailnet ── bastion (subnet router, same VPC / VNet)
```

## Turning it on

```json
"kubernetes": {
  "managed": true,
  "node_count": 3,
  "node_size": "medium"
}
```

That is the whole change. Keep the `k3s-1`, `k3s-2`, `k3s-3` entries in `vms`:
Terraform skips those VMs while `managed` is `true`, but the first one's
`secret_mappings` still names the secret containers the cluster needs and its
`public_endpoint` still names the site. Setting `managed` back to `false`
brings the VMs back.

Optional fields (see `project-config.schema.json`):

| Field | Default | Meaning |
| --- | --- | --- |
| `cloud` | `default_cloud` | `gcp`, `aws` or `azure`. The bastion must be in the same cloud. |
| `version` | provider's current | Kubernetes minor version, e.g. `"1.33"`. |
| `node_count` | `3` | Nodes in the single node pool. |
| `node_size` | `medium` | Portable size, through `catalog.size`. |
| `node_disk_gb` | `30` | Boot disk per node. |
| `node_subnet_cidr` | third `/24` of the cloud's `vpc_cidr` | Node subnet (on AWS the fourth `/24` is added in a second zone). |
| `pod_cidr` | `10.40.0.0/16` | GKE secondary range / AKS overlay. EKS pods use node-subnet addresses. |
| `service_cidr` | `10.41.0.0/20` | ClusterIP range. |
| `control_plane_cidr` | `172.16.0.0/28` | GKE only: the private control plane's peering range. |
| `api_allowed_cidrs` | the bastion's `allowed_cidrs` | Who may reach the public API endpoint (Ansible, kubectl). |

## What Terraform creates

**GKE** (`modules/gcp/kubernetes`)
- a zonal cluster (the free tier covers its control plane) with private nodes;
- a node subnet with the pod and Service ranges as secondary ranges, and its own Cloud NAT;
- a node service account with only the logging and metrics roles, instead of the
  Compute Engine default account;
- a firewall rule from the control plane to the nodes for admission webhooks
  (CloudNativePG 9443, the Prometheus operator and cert-manager), which GKE does
  not open on its own for private clusters;
- the API endpoint public but limited to `api_allowed_cidrs`.

**EKS** (`modules/aws/kubernetes`)
- the cluster with access entries (`authentication_mode = API`); whoever runs
  Terraform becomes cluster admin, the same identity Ansible uses;
- two node subnets, because EKS needs two zones; the nodes and both load
  balancers stay in the bastion's zone, behind the existing NAT gateway;
- a managed node group (Amazon Linux 2023);
- the EBS CSI driver add-on with its permissions through EKS Pod Identity, for
  the volumes CloudNativePG and Prometheus claim.

**AKS** (`modules/azure/kubernetes`)
- the cluster (Free tier) with Azure CNI overlay in a node subnet of its own;
- Network Contributor on the VNet for the cluster identity, so the internal
  load balancer can take an address in it;
- the API endpoint public but limited to `api_allowed_cidrs`.

`terraform output kubernetes` shows the cluster's name, location and the
kubeconfig context name.

## What Ansible does differently

1. **Credentials** - the `managed_kubernetes` role runs one of
   `gcloud container clusters get-credentials`, `aws eks update-kubeconfig` or
   `az aks get-credentials` into `~/.kube/<name_prefix>-<environment>.yaml`
   and waits for every node to be Ready. On EKS it also adds a default `gp3`
   StorageClass.
2. **Current context** - the `kube_context` role merges that file into
   `~/.kube/config` (a timestamped backup of the old one is kept next to it)
   and makes the stand's context the current one, so plain `kubectl`,
   `kubectx` and `k9s` work. This also happens for k3s.
   `OILSCOPE_SET_CONTEXT=false` leaves `~/.kube/config` alone.
3. **Secrets** - there is no node VM to read them, so `resolve_secrets` reads
   the same containers from the controller with the operator's `gcloud`, `aws`
   or `az` login. They still only reach the cluster as Kubernetes Secrets.
4. **Traefik** - instead of host ports on the nodes it sits behind two cloud
   load balancers, both with `externalTrafficPolicy: Local` so the visitor's
   own address survives and the internal-only allow lists still work:
   `traefik` (internet-facing) and `traefik-internal` (private address in the VPC/VNet).
   On AWS both are Network Load Balancers.
5. **DNS** - the public load balancer's address exists only after Traefik is
   installed, so Ansible writes the Cloudflare record (A, or CNAME for an AWS
   NLB) with the `CF_DNS_API_TOKEN` cert-manager already uses, and points the
   bastion's CoreDNS (`*.oilscope.internal`) at the internal load balancer.

## Running it

Prerequisites on the controller, besides what k3s needed:

| Cloud | Needs |
| --- | --- |
| GKE | `gcloud components install gke-gcloud-auth-plugin` |
| EKS | AWS CLI v2, logged in as the identity that runs Terraform |
| AKS | Azure CLI (`az login`) |

```bash
cd infrastructure/terraform
terraform plan  -var="project_config_path=$OILSCOPE_PROJECT_CONFIG" -out=tfplan
terraform apply tfplan          # roughly: GKE 8 min, AKS 6 min, EKS 15 min

cd ../..
ansible-playbook oilscope.platform.site \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"

kubectl get nodes -o wide        # the managed nodes, from the new current context
kubectl get svc -n traefik       # the two load balancers and their addresses
```

## Moving between clouds

One stand runs one cluster. To show the same application on another cloud,
use a configuration per cloud (they can share everything but these lines):

| Field | GKE | EKS | AKS |
| --- | --- | --- | --- |
| `default_cloud` | `gcp` | `aws` | `azure` |
| `vms.bastion.internal_ip` | `10.10.0.10` | `10.20.0.10` | `10.30.0.10` |

The bastion follows `default_cloud`, which puts it next to the cluster: it is
the tailnet's way to the internal load balancer. Applying another cloud's
configuration in the same Terraform workspace moves the stand - the old
cluster and bastion are destroyed, the new ones created. After a move, forget
the old bastion's host key (`ssh-keygen -R`) as after any rebuild.

## Dashboards

kube-prometheus-stack brings the cluster, node and container dashboards with
it, on the managed clusters as on k3s - in Grafana under *Dashboards*:

- *Kubernetes / Compute Resources / Cluster* - CPU, memory and network per namespace;
- *Node Exporter / Nodes* and *Kubernetes / Compute Resources / Node (Pods)* - per node;
- *Kubernetes / Compute Resources / Pod* - per container;
- *OilScope* - the application's own.

The managed control plane itself (API server internals, etcd, scheduler) is the
provider's, and is not scraped.

## Things to know

- **Cost.** GKE's zonal control plane is covered by the free tier and AKS's
  Free tier costs nothing; EKS charges for the control plane by the hour
  (about USD 0.10). The nodes are billed like the k3s VMs were. Destroy the
  stand after a demo.
- **Azure quota.** Three `medium` nodes are 12 vCPUs (`Standard_D4as_v7`); a
  new subscription's regional quota may be lower. Use `"node_size": "small"`
  or raise the quota.
- **The Cloudflare record belongs to Ansible while `managed` is `true`.**
  Terraform does not track it. Before switching back to k3s, delete the record
  (or let `terraform apply` fail once on "record already exists", delete it,
  and apply again).
- **GKE volumes start at 10 GB**, so on GKE the Prometheus and database claims
  are raised to 10 Gi.
