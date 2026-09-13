# TLS and DNS for the UI's public endpoint

The UI VM terminates HTTPS itself: `edge_proxy` runs Traefik, and Traefik
gets its certificate from Let's Encrypt with a DNS-01 challenge answered
through the Cloudflare API, using the hostname in `public_endpoint.hostname`.
Unlike an HTTP or TLS-ALPN challenge, DNS-01 never touches port 443 to prove
anything - it only needs the zone's `_acme-challenge` TXT record to be
writable, which Traefik does itself via Cloudflare's API on every renewal.

That still leaves the hostname itself needing to resolve to the VM for actual
traffic. Terraform can manage that too, one field away:

```json
"public_endpoint": {
  "hostname": "example.example.com",
  "acme_email": "example-operator@example.com",
  "cloudflare_zone_id": "0123456789abcdef0123456789abcdef"
}
```

Leave `cloudflare_zone_id` out and nothing changes: point the hostname at the
VM's public IP however you already do, outside Terraform.

Set it, and the `cloudflare` module creates one DNS record - an `A` record at
`hostname`, in that zone, pointing at `workload_external_ips.ui` - every time
the VM's public IP changes as much as when it is first created. The record is
always created unproxied - Cloudflare's grey cloud, not the orange one - so
traffic reaches the VM directly rather than through Cloudflare's edge.

## Two tokens, two purposes

**Terraform's token** creates the `A` record. It is never written to the
project configuration, a `.tfvars` file, or committed anywhere:

```bash
export TF_VAR_cloudflare_api_token=...
```

**Traefik's token** answers the DNS-01 challenge from the VM itself, so it
travels the same way every other application secret does here: a
`secret_mappings` entry on the `ui` vm,

```json
"secret_mappings": {
  "CF_DNS_API_TOKEN": "example-cloudflare-dns-token"
}
```

resolved by `resolve_secrets` and handed to the Traefik container as a process
environment variable at `docker compose up` - never written to a file on the
VM, exactly like `POSTGRES_PASSWORD` for the other workloads.

Both tokens can be the same value. Scope it to `Zone:DNS:Edit` on the one zone
in `cloudflare_zone_id`, nothing wider - it needs no other Cloudflare
permission, on this project or any other zone.
