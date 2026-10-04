# k3s

Installs k3s on the hosts of the `k3s_server` and `k3s_agent` groups, which the
oilscope inventory plugin builds from the VMs' role labels. Grown out of
the single-server Multipass lab that used to live in `labs/k3s` (see the git
history), with the single-server limit replaced by embedded etcd.

- The first server of the group starts etcd with `cluster-init`; the others join
  it with the token it wrote. Run them one at a time (`serial: 1`), as
  `playbooks/cluster.yml` does, so the quorum grows by one member at a time.
- The role refuses an even number of servers: two cannot form a majority.
- The binary comes from the GitHub release and is checked against the published
  SHA-256, so a second run downloads nothing and a new `k3s.version` downloads
  exactly once. Configuration lives in `/etc/rancher/k3s/config.yaml`; a change
  to it restarts the service through a handler instead of being skipped.
- `node-ip` and `advertise-address` are the private address from the inventory, `node-external-ip` the
  public one when there is one, and `tls-san` covers every server's addresses
  plus `k3s.tls_sans` from the project configuration.
- The bundled Traefik is disabled; `cluster_platform` installs it from Helm.
- The administrator kubeconfig is copied to `oilscope_kubeconfig` on the
  controller, pointed at `k3s.api_endpoint` or the first server's private
  address.

## Variables

See `defaults/main.yml`. The ones worth changing are read from the project
configuration: `k3s.version`, `k3s.api_endpoint`, `k3s.tls_sans`.
