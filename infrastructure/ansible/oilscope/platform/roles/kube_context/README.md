# kube_context

Makes the stand's cluster the operator's current kubectl context. Merges the
stand's own kubeconfig (`oilscope_kubeconfig`, written by `k3s` or
`managed_kubernetes`) into `~/.kube/config`:

- the stand's clusters, users and contexts replace entries of the same name -
  a rebuilt cluster keeps its name but gets a new certificate;
- every other entry is kept;
- `current-context` becomes the stand's;
- the previous file is kept next to it as a timestamped backup.

This is what `kubectl config view --flatten` followed by
`kubectl config use-context` would do, without needing kubectl. Afterwards
`kubectl`, `kubectx`, `k9s`, Lens and Headlamp's desktop app reach the stand
with no `--kubeconfig`; `kubectx` switches back.

| Variable | Default |
| --- | --- |
| `kube_context_source` | `oilscope_kubeconfig` |
| `kube_context_target` | `~/.kube/config` |
| `kube_context_enabled` | `true`; `OILSCOPE_SET_CONTEXT=false` turns it off |
