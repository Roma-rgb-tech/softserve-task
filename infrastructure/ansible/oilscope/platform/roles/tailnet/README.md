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

`bootstrap_bastion.yml` runs the role only when the project configuration has a
`tailscale` block.

## Variables

- `tailnet_config_path`: the project configuration; defaults to
  `project_config_path`.
- `tailnet_api_key_variable`: environment variable holding the access token.
- `tailnet_repository_release`: Ubuntu release of the Tailscale packages.
- `tailnet_auth_key_ttl_seconds`: lifetime of the single-use auth key.
