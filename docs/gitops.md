# GitOps with Argo CD

With GitOps on, nobody applies the OilScope services to the cluster by hand or
from a laptop. Their desired state is the Helm chart in `deploy/helm/oilscope`,
and Argo CD, running inside the cluster, keeps the cluster equal to it:

```
 git push ──► GitHub (deploy/helm/oilscope @ revision)
                    ▲
                    │  pull every 2-3 minutes
              ┌─────┴──────┐   helm template   ┌──────────────────────────┐
              │  Argo CD   │ ────────────────► │ namespace oilscope       │
              │ (argocd ns)│   apply, prune,   │ history, fetcher, ui,    │
              └────────────┘   self-heal       │ Ingress for the UI       │
                                               └──────────────────────────┘
```

- **Pull, not push.** CI and the operator's laptop need no cluster credentials
  to deploy; the cluster fetches what to run.
- **Git is the audit log.** Every change to the services is a commit; a
  rollback is `git revert`.
- **Drift is undone.** `selfHeal` puts back anything changed with `kubectl`
  (scale a Deployment by hand and Argo CD scales it back); `prune` deletes what
  was removed from the chart.

## Turning it on

```json
"kubernetes": {
  "managed": true,
  "gitops": {
    "enabled": true,
    "repo_url": "https://github.com/<org>/<repo>.git",
    "revision": "main"
  }
}
```

`revision` is the branch (or tag, or commit) Argo CD follows. The repository is
public, so Argo CD reads it without credentials. Push the branch first: Argo CD
reads GitHub, not the working tree. Then run the playbook as usual:

```sh
ansible-playbook oilscope.platform.site \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

## What the playbook does

| Step | Role | GitOps off | GitOps on |
| --- | --- | --- | --- |
| Platform layer | `cluster_platform` | Traefik, cert-manager, CloudNativePG, monitoring, Headlamp | the same, plus `argo-cd` in `argocd`, and on AKS `external-secrets` |
| Application secrets | `cluster_app` | written by Ansible from the cloud secret store | on AKS: the `oilscope-secrets` Application, External Secrets copies them from Key Vault; elsewhere written by Ansible |
| Redis, database | `cluster_app` | applied by Ansible | applied by Ansible |
| Migrations | `cluster_app` | a Job per image tag, run by Ansible | a PreSync hook of the `oilscope` Application, run before every rollout |
| history, fetcher, ui, Ingress | `cluster_app` | `helm template` of the chart, applied by Ansible | the `oilscope` Application; Ansible waits until it is *Synced* and *Healthy* |
| `argocd.<internal_domain>` | `internal_dns` | - | a record on the bastion's DNS, like Grafana's |

The stand-specific values (image repository, public hostname, the Key Vault and
its identity) come from the project configuration and Azure, and are written
into each Application's `helm.valuesObject`. The image **tag** is not: it lives
in Git.

## Releasing a new image

```
merge to develop ──► Publish application images ──► images :<sha> in GHCR
                              │
                              └─ promote job: image.tag: "<sha>" in
                                 deploy/helm/oilscope/values.yaml, committed
                                 to the same branch
                                              │
                         Argo CD sees the commit ┘──► PreSync: migrate
                                                      └─► rolling update
```

- The `promote` job in `.github/workflows/publish-images.yaml` runs after the
  four images are pushed, for any branch build (pushes to `develop` and `main`,
  or *Run workflow* on another branch). It never moves the tag backwards: a
  build older than the one already in the chart changes nothing.
- It pushes with `GITHUB_TOKEN`, and GitHub starts no workflow for such a
  push, so the promotion cannot trigger another build. On a protected branch
  the push is refused and the job opens a pull request with the change instead.
- Rolling back a release is a revert of the promotion commit.
- Without GitOps nothing changes: Ansible still deploys `registry.image_sha`
  from the project configuration.

## Secrets with External Secrets (AKS)

No secret value is in Git or in the Argo CD Applications. On AKS:

1. Terraform turns on the cluster's OIDC issuer and workload identity and
   creates the managed identity `<prefix>-external-secrets`, with a federated
   credential that trusts the `oilscope-secrets` service account in the
   application namespace, and *Key Vault Secrets User* on each of the
   cluster's secrets (one secret at a time, never the whole vault).
2. `cluster_platform` installs the External Secrets Operator.
3. `cluster_app` creates the `oilscope-secrets` Application for
   `deploy/helm/oilscope-secrets`: the service account, a `SecretStore` for the
   vault, and one `ExternalSecret` per Kubernetes Secret (`oilscope-registry`,
   `oilscope-db-app-user`, `oilscope-redis`, `oilscope-app`). The templates in
   the ExternalSecrets build the registry login and the connection strings
   from the raw values.
4. External Secrets re-reads Key Vault every 10 minutes. Rotating a value is
   now: put a new version in Key Vault (`upload_secret_versions.yml`, or the
   portal), wait for the refresh, restart the pods that read it. Ansible does
   not touch the cluster.

```sh
kubectl -n oilscope get externalsecrets     # STATUS SecretSynced, READY True
# Force a refresh now instead of waiting for the interval:
kubectl -n oilscope annotate externalsecret oilscope-registry force-sync=$(date +%s) --overwrite
```

On GKE and EKS GitOps still works; the secrets are written by Ansible as
before.

## Signing in

The UI answers only over the tailnet, at `http://argocd.oilscope.internal`
(the internal domain of the stand). The user is `admin`; the password is
generated on install:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d | pbcopy
```

The CLI works too: `argocd login argocd.oilscope.internal --insecure --grpc-web`.

## Showing it works

```sh
kubectl -n argocd get applications            # oilscope and oilscope-secrets: Synced Healthy

# Drift: scale by hand, watch Argo CD put it back within seconds
kubectl -n oilscope scale deployment ui --replicas=0
kubectl -n oilscope get deployment ui -w

# A change through Git: bump replicas in deploy/helm/oilscope/values.yaml,
# commit, push to the followed branch; the Application goes OutOfSync, then
# Synced, and the second ui pod appears.
```

Argo CD's own metrics (sync status, reconcile time, Git requests) are scraped
by Prometheus through the chart's ServiceMonitors.

## Limits and next steps

- Redis and the database stay in Ansible: they are bootstrap and stateful
  steps that run once per stand. The database image (CloudNativePG's
  `ImageCatalog`) still follows `registry.image_sha`.
- External Secrets covers Azure only; GCP Secret Manager and AWS Secrets
  Manager need the same workload identity setup on GKE and EKS.
- Argo CD itself is installed by Ansible (a bootstrap has to start
  somewhere). It could then manage the rest of the platform layer as more
  Applications (the app-of-apps pattern).
