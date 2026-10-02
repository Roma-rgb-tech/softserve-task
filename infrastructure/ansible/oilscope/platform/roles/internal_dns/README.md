# internal_dns

Gives the operator pages - Headlamp, Homepage, Grafana, Prometheus - real
names instead of lines in `/etc/hosts`.

- CoreDNS runs on every bastion from its release binary, checked against the
  published checksum, and listens on the bastion's private address only.
- It answers for `cluster.internal_domain` (`oilscope.internal` by default):
  each page's name resolves to every k3s node's private address, since Traefik
  runs on all of them.
- Through the Tailscale API the tailnet's split DNS sends that domain to the
  bastions. A device in the tailnet that accepts Tailscale's DNS settings - the
  default - resolves the names with no setup of its own, and reaches the
  bastion's address through the subnet route the bastion advertises.

The pages themselves still answer only to the clouds' private ranges, so the
names are useless outside the tailnet.

```bash
dig @10.10.0.10 grafana.oilscope.internal +short   # from the tailnet
```
