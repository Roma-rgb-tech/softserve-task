# k3s lab

A learning cluster, kept apart from the OilScope stand on purpose: the
application still runs on VMs with Docker Compose. The goal here is to see
what a Kubernetes cluster is made of, so a managed one (GKE, EKS, AKS) stops
being a black box.

The role is written from scratch rather than taken from an existing
collection. It installs the release binary instead of piping the upstream
install script into a shell, so every step the script would hide is a task
you can read.

## What the role does

| Step | Server | Agent |
| --- | --- | --- |
| Kernel modules `overlay`, `br_netfilter` and the forwarding sysctls | yes | yes |
| `/usr/local/bin/k3s` from the GitHub release, checked against its SHA-256 | yes | yes |
| `kubectl`, `crictl`, `ctr` as links to the same binary | yes | yes |
| `/etc/rancher/k3s/config.yaml` | `node-ip`, `tls-san` | `server`, `token-file`, `node-ip` |
| systemd unit | `k3s.service` (`k3s server`) | `k3s-agent.service` (`k3s agent`) |
| Join token | read from `/var/lib/rancher/k3s/server/node-token` | written to `/etc/rancher/k3s/cluster-token`, mode `0600` |
| Readiness | waits for `/readyz` | waits until the server lists the node `Ready` |

The token never appears on a command line or in the Ansible output
(`no_log`). The agent reads it from a root-only file, which is what k3s
itself does with the token it is given.

The server's kubeconfig is copied to `labs/k3s/kubeconfig` (ignored by git)
with `127.0.0.1` replaced by the server address, so `kubectl` works from the
controller.

## Three VMs with Multipass

```bash
brew install multipass
for n in k3s-server k3s-agent-1 k3s-agent-2; do
  multipass launch 24.04 --name "$n" --cpus 2 --memory 2G --disk 10G \
    --cloud-init <(printf 'ssh_authorized_keys:\n  - %s\n' "$(cat ~/.ssh/id_ed25519.pub)")
done
multipass list
```

Copy `inventory.example.yml` to `inventory.yml` and put the addresses
`multipass list` printed into it.

## Run

```bash
cd labs/k3s
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory.yml site.yml
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
```

A second run changes nothing.

## Something to look at

```bash
kubectl apply -f demo/whoami.yaml
kubectl -n lab get pods -o wide
kubectl -n lab get endpoints whoami
curl -s http://<server-ip>/ | grep Hostname
```

Repeat the `curl`: the hostname changes, because Traefik (the ingress
controller k3s ships) sends each request to the `whoami` Service, and the
Service spreads them over the three pods on different nodes.

```bash
kubectl -n lab delete pod -l app=whoami --wait=false
kubectl -n lab get pods -w
```

The Deployment's ReplicaSet notices the missing pods and starts new ones -
the "cattle, not pets" idea in one command.

## What runs inside

```bash
kubectl get pods -A
sudo k3s crictl ps
```

- **API server, scheduler, controller manager** - all in the single `k3s
  server` process, not as pods. A managed cluster hides exactly this part.
- **Datastore** - SQLite through kine instead of etcd, because there is one
  server. Several servers would need embedded etcd or an external database.
- **kubelet and containerd** - in every `k3s` process, server included, so the
  server is also a node.
- **flannel** - the pod network, VXLAN between the nodes.
- **CoreDNS** - names like `whoami.lab.svc.cluster.local`.
- **Traefik** - the ingress controller; **ServiceLB** answers for
  `LoadBalancer` services on the node addresses.
- **metrics-server** - `kubectl top nodes`.

## Clean up

```bash
multipass delete --purge k3s-server k3s-agent-1 k3s-agent-2
rm -f kubeconfig
```
