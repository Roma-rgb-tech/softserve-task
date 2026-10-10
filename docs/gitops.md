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
| Platform layer | `cluster_platform` | Traefik, cert-manager, CloudNativePG, monitoring, Headlamp | the same, plus the `argo-cd` chart in `argocd` |
| Secrets, Redis, database, migrations | `cluster_app` | applied by Ansible | applied by Ansible (unchanged) |
| history, fetcher, ui, Ingress | `cluster_app` | `helm template` of the chart, applied by Ansible | an Argo CD `Application` for the chart; Ansible waits until it is *Synced* and *Healthy* |
| `argocd.<internal_domain>` | `internal_dns` | - | a record on the bastion's DNS, like Grafana's |

Secrets stay out of Git: the role still creates `oilscope-app` and
`oilscope-registry` from the cloud secret store, and the chart only refers to
them by name. The stand-specific values (image repository and tag, public
hostname) come from the project configuration and are written into the
Application's `helm.valuesObject`.

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
kubectl -n argocd get applications            # oilscope   Synced   Healthy

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

- The image tag is still chosen by the project configuration. The next step is
  to keep it in Git as well, with CI (or Argo CD Image Updater) committing the
  new tag after `publish-images` pushes an image.
- Redis, the database and the migrations stay in Ansible: they are bootstrap
  and stateful steps that run once per stand.
- Argo CD itself is installed by Ansible (a bootstrap has to start
  somewhere). It could then manage the rest of the platform layer as more
  Applications (the app-of-apps pattern).
