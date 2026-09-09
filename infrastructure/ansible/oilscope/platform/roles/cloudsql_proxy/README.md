# cloudsql_proxy

Installs the Cloud SQL Auth Proxy as a systemd service and leaves it listening
for the workloads on this machine.

Cloud SQL over Private Service Connect is not something a container can simply
open a socket to: the session is authenticated with Google credentials, not with
a password alone. The connector holds that session. The application connects to
the connector in plain PostgreSQL, and the connector connects onward over TLS as
the machine's own service account - which Terraform granted
`roles/cloudsql.client` and nothing else. No key file is ever written to the
host.

The proxy listens on the machine's private address rather than on the loopback,
because the services run in containers and inside a container `127.0.0.1` is the
container. Nothing outside the machine can reach that port: no firewall rule
allows it.

## Variables

- `cloudsql_proxy_connection_name` (required): `project:region:instance`. The
  connector resolves no hostname, so this is the only handle it accepts.
- `cloudsql_proxy_address`, `cloudsql_proxy_port`: where it answers.
- `cloudsql_proxy_version`, `cloudsql_proxy_url`, `cloudsql_proxy_binary`.
- `cloudsql_proxy_health_address`, `cloudsql_proxy_health_port`.
