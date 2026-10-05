# managed_kubernetes

Connects the controller to the managed cluster Terraform created when
`kubernetes.managed` is `true` - GKE, EKS or AKS - and, once the platform is
installed, points the stand's names at it. Runs on `localhost` only, with the
operator's own `gcloud`, `aws` or `az` login.

## Tasks

`main.yml` (in `cluster.yml`, before anything is installed):

- writes the cluster's credentials into `oilscope_kubeconfig`
  (`~/.kube/<name_prefix>-<environment>.yaml`) with
  `gcloud container clusters get-credentials`, `aws eks update-kubeconfig` or
  `az aks get-credentials`, and sets `managed_kubernetes_context`;
- waits until `kubernetes.node_count` nodes are Ready;
- on EKS, adds a default `gp3` StorageClass on the EBS CSI driver.

`ingress.yml` (after `cluster_platform`):

- waits for Traefik's two LoadBalancer Services, `traefik` and
  `traefik-internal`, to get their addresses;
- writes the Cloudflare record for `public_endpoint.hostname` - an A record for
  an IP (GKE, AKS), a CNAME for an AWS load balancer name - replacing whatever
  address record was there;
- sets `managed_kubernetes_internal_address`, which `cluster.yml` hands to
  `internal_dns` on the bastion.

## Variables

| Variable | Default | |
| --- | --- | --- |
| `managed_kubernetes_cloud` | `oilscope_kubernetes_cloud` | `gcp`, `aws` or `azure` |
| `managed_kubernetes_name` | `<prefix>-<env>-<gke\|eks\|aks>` | as Terraform names it |
| `managed_kubernetes_kubeconfig` | `oilscope_kubeconfig` | |
| `managed_kubernetes_cloudflare_token` | `""` | `CF_DNS_API_TOKEN`, for `ingress.yml` |
| `managed_kubernetes_wait_retries` / `_delay` | `60` / `10` | for nodes and load balancers |

## Requirements

- GKE: `gke-gcloud-auth-plugin` (`gcloud components install gke-gcloud-auth-plugin`).
- EKS: AWS CLI v2, as the identity that ran Terraform (it holds the cluster
  admin access entry).
- AKS: Azure CLI.
- `kubernetes.core` for the Kubernetes modules.
