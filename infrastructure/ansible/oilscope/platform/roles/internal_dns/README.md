# internal_dns

Gives the operator pages - Headlamp, Homepage, Grafana, Prometheus - real
names instead of lines in `/etc/hosts`.

- [Technitium DNS Server](https://technitium.com/dns/) runs on every bastion
  (`internal_dns_server: technitium`, the default) as a container on the host
  network, listening on the bastion's private address only. Its web console is
  at `http://dns.oilscope.internal:5380` over the tailnet; user `admin`, the
  password is invented on the first run and kept on the bastion:
  `sudo cat /var/lib/technitium/admin-password`. The role creates the zone and
  the records through Technitium's HTTP API, and turns recursion off - it
  answers only for its own zone.
- Docker is installed with `iptables: false`: the bastion is the tailnet's
  subnet router, and Docker's own firewall rules would drop forwarded traffic.
- `internal_dns_server: coredns` keeps the previous server: CoreDNS from its
  release binary, checked against the published checksum.
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
