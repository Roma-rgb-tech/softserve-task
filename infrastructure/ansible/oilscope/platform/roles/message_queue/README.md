# message_queue

Runs RabbitMQ on the VM with role `database`, and applies the database
migrations from there.

The VM exists in both modes, and what it carries depends on one flag. With
`database.managed` off it runs the PostgreSQL container, and the queue lives
inside that database as a PGMQ queue. With the flag on, PostgreSQL moves to
Cloud SQL or RDS - neither of which has the PGMQ extension - so the queue has to
become a broker of its own, and this is where it runs.

Migrations run from here in both modes, for the same reason: one machine owns
the schema, whether the server it talks to is a container beside it or a managed
instance across the private network.

## Variables

- `message_queue_user`, `message_queue_password`, `message_queue_vhost`: the
  broker credentials. The password comes from the secret container named by
  `database.queue_password_secret`.
- `message_queue_database_*`: where the migrations are applied.
- `message_queue_bind_address`, `message_queue_host_port`: where the broker
  answers. Only the workload security group or network tag may reach it.
