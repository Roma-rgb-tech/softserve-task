# managed_database

Makes the application's credentials in the managed database match the project's
secret container. Runs on the operator's machine, not on a VM: it needs
administrative access to the database, and no workload should have that.

The two clouds keep the password in opposite places, and the role moves it in
opposite directions.

**GCP.** Cloud SQL cannot generate a password nobody has seen, so the project's
container stays the source. The role reads it and creates - or updates - the
application role on the instance through the Cloud SQL Admin API. The value
travels in a request body, never as a command-line argument.

**AWS.** RDS was created with `manage_master_user_password`, so it invented the
password itself and keeps it in a container of its own. Terraform never saw it.
The role reads that container and copies the value into the project's own, which
is what `resolve_secrets` and the compose environment already read.

Either way the services read one container, and Terraform reads none. Running it
again sets the same password again: that is how a rotated secret reaches the
instance, and how a half-finished earlier run is repaired.

## Variables

- `managed_database_config_file` (required): the project configuration, the same
  file Terraform reads.
- `managed_database_gcloud`, `managed_database_aws`: the CLIs to call.
- `managed_database_api`: Cloud SQL Admin API base URL.
