# tailnet

Joins the bastion of each cloud to one tailnet as a subnet router, so a
workload in one cloud reaches the private addresses of the others. Terraform
routes the ranges of the other clouds to the bastion; this role makes the
bastion carry them.

The role authenticates with a Tailscale API access token read from
`$TAILSCALE_API_KEY` on the controller. It never reaches the bastion: the role
asks the API for a single-use, short-lived auth key, hands that key to
`tailscale up` on stdin, then approves the advertised route and turns off key
expiry for the node through the API.

Tailscale runs with an MTU of 1280, while the VPCs use 1460 (GCP) or 1500
(AWS, Azure, Docker bridges). A TCP handshake fits in either, so a plain port
check succeeds, but the first full-size segment - the server certificate in a
TLS handshake to PostgreSQL, for instance - is dropped on the bastion, and the
ICMP message that would tell the sender to shrink it never gets back. The
connection then hangs until it times out. The role installs
`oilscope-tailnet-mss.service`, which clamps the TCP MSS of every connection
forwarded through `tailscale0` to the path MTU, so both ends agree on segments
that fit from the first packet.

`bootstrap_bastion.yml` runs the role only when the project configuration has a
`tailscale` block.

## Variables

- `tailnet_config_path`: the project configuration; defaults to
  `project_config_path`.
- `tailnet_api_key_variable`: environment variable holding the access token.
- `tailnet_repository_release`: Ubuntu release of the Tailscale packages.
- `tailnet_auth_key_ttl_seconds`: lifetime of the single-use auth key.
- `tailnet_interface`: the Tailscale network interface.
- `tailnet_mss_unit`: the systemd unit that keeps the MSS clamping.
