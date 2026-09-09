# The database

PostgreSQL lives in one of two places, and one flag in the project configuration
decides which:

```json
"database": {
  "managed": true,
  "engine_version": "16",
  "size": "micro",
  "storage_gb": 20,
  "database_name": "oil_tracker",
  "username": "oil_tracker",
  "password_secret": "oilscope-dev-db-password",
  "backup_retention_days": 7,
  "deletion_protection": false
}
```

Leave the block out, or set `managed` to false, and nothing changes from before:
the VM with role `database` runs the PostgreSQL container and the other
workloads connect to its private address.

Turn it on and the cloud runs the database instead - Cloud SQL on GCP, RDS on
AWS. The VM with role `database` does not disappear: it changes what it carries.

That is the part worth understanding, because it is not obvious. The queue
between the fetcher and the history service is not a broker - it is PGMQ, a
queue that lives inside PostgreSQL as an extension. Neither Cloud SQL nor RDS
offers that extension, and no amount of configuration will produce it. So moving
PostgreSQL to the cloud takes the queue with it, and something has to replace
it. That something is RabbitMQ, running in a container on the same VM the
database used to occupy.

```json
"database": {
  "queue_username": "oil_tracker",
  "queue_vhost": "oil_tracker",
  "queue_password_secret": "oilscope-dev-queue-password"
}
```

The services carry both paths. The fetcher publishes through a `service.Publisher`
that is either the PGMQ implementation or the AMQP one; the history service
consumes through `create_consumer`, which returns either `PGMQConsumer` or
`AMQPConsumer`. Both are chosen by one environment variable, `QUEUE_BACKEND`,
which Ansible derives from the same flag Terraform reads. Nothing else in either
service knows which one is running.

The idempotency guarantee is kept in both, but it is not identical. On PGMQ the
claim in `published_queue_events` and the send happen in one transaction, so a
message is published exactly once. Over AMQP the claim is committed first and
the publish follows, with the claim released again if the broker refuses - which
narrows the window rather than closing it. A crash between the two would drop
one batch of prices; the next scheduled run collects them again.

The database migrations run from that VM in both modes, because one machine
should own the schema. The migration that creates the PGMQ queue checks
`pg_available_extensions` first and does nothing on a server that has no PGMQ,
so the same migration set applies to both.

## A network of its own

The database is not put in the workload subnet. It gets ranges of its own:

```json
"network": {
  "database_subnet_cidrs": ["10.10.2.0/24", "10.10.3.0/24"]
}
```

They carry no route to the internet in either direction - they stay on the VPC's
main route table, which knows only the local range - so the only way to the
database is from inside the VPC.

**AWS** spreads a DB subnet group over both of them. RDS refuses a subnet group
that does not span two availability zones, even for a single instance that will
only ever sit in one, so the ranges are placed in the first two zones the region
offers rather than pinned to the one zone the VMs use.

**GCP** uses the first range for a Private Service Connect endpoint. This is the
part worth explaining at a review, because the older mechanism - private
services access - looks similar and is not the same thing. With private services
access the instance gets an address in a range that is peered into the VPC but
owned by Google, in a project that is not yours. With Private Service Connect
the instance publishes a service attachment, and a forwarding rule in your own
subnet points at it. The address the workloads talk to is an address in
`oilscope-dev-database`, allocated from a range this configuration chose.

## The connector

On AWS the workloads open a socket to the RDS endpoint and that is the whole
story: a security group lets the fetcher, the history service and the UI in on
5432, and nothing else.

On GCP they do not. Cloud SQL authenticates the session with Google credentials
rather than with a password alone, so the connection is made by the Cloud SQL
Auth Proxy running on each machine as a systemd service. The application
connects to the proxy in plain PostgreSQL; the proxy connects onward over TLS as
the machine's own service account, which holds `roles/cloudsql.client` and
nothing more. No key file is written anywhere.

The proxy listens on the machine's private address, not on the loopback. The
services run in containers, and inside a container `127.0.0.1` is the container.

The proxy does not dial the endpoint address. It asks the Admin API for the
instance's own DNS name - something like
`52fbddde28ed.1y4uafloceyrt.us-east1.sql.goog` - and resolves that. With private
services access Google publishes that record itself. With Private Service
Connect it does not: the name is expected to resolve inside your VPC, to your
endpoint. So the module creates a private Cloud DNS zone for that name and an A
record in it pointing at the forwarding rule's address. Without it the proxy
fails with `no such host` and nothing reaches the database. This needs
`dns.googleapis.com` enabled in the project.

## Where the password lives

Nowhere in Terraform - not in the configuration, not in the plan, not in the
state. Beyond that the two clouds are handled differently, because they offer
different things.

**AWS** can generate a master password, keep it in Secrets Manager and rotate it
there without Terraform ever seeing the value, so it does:
`manage_master_user_password = true`. After the instance exists, the
`managed_database` role copies that value into the project's own secret
container - the one `resolve_secrets` and the compose environment already read -
so nothing downstream has to know where it came from.

**GCP** has no equivalent, so the project's container stays the source. The same
role reads it and creates, or updates, the application role on the instance
through the Cloud SQL Admin API, passing the password in a request body rather
than as a command-line argument.

The role runs on the operator's machine rather than on a VM. Creating a database
role needs administrative access, and no workload should hold that.

## Running it

Unchanged, and in this order:

```bash
terraform apply -var=project_config_path=/absolute/path/project-config.json

ansible-playbook oilscope.platform.site \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`site.yml` reconciles the credentials after the secret containers are filled and
before any workload connects. `terraform output database` names the host, the
port, the database, the application role and the container holding its password
- never the password.

## The extension the migrations do need

`pgcrypto` and `hstore` are present on both managed services. `pg_cron` is not,
until it is asked for, and the UI session cleanup is scheduled with it - so
Terraform asks: a `cloudsql.enable_pg_cron` database flag on Cloud SQL, and a
parameter group carrying `shared_preload_libraries = pg_cron` on RDS. Both also
set `cron.database_name` to the application database, because the default is
`postgres` and the job would otherwise be scheduled in the wrong place.

## Switching back

Set `managed` to false and apply. Terraform destroys the instance, the subnets
and the endpoint; Ansible then finds the same VM carrying the wrong thing and
replaces the broker with the PostgreSQL container, and the services fall back to
publishing into PGMQ. Nothing else in the configuration changes.

The data does not come with it - that is a restore, not a flag - and neither do
the messages still sitting in the queue. Drain the queue before switching in
either direction, or accept losing whatever has not been consumed yet.

Two things to know before the first run. A deleted Cloud SQL instance keeps its
name reserved, so re-creating it with the same name shortly afterwards fails;
the fix is to wait or to change `environment`. And on RDS the backup window
makes creation and deletion noticeably slower, so `backup_retention_days: 0`
while testing saves real minutes on every cycle.
