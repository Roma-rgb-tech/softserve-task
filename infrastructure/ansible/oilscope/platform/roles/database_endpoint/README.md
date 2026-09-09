# database_endpoint

Works out the address the workloads on this host use to reach PostgreSQL, and
records it as `oilscope_database_host`. Every workload role reads that one
variable, so none of them contains a branch of its own.

There are three answers and the role picks between them:

| | address |
| --- | --- |
| PostgreSQL in a container | the private address of the VM with role `database` |
| Cloud SQL | this machine's own private address, where the connector listens |
| RDS | the endpoint RDS invented, asked for once from the operator's machine |

The RDS endpoint is the only value in the deployment that cannot be derived from
the project configuration - AWS generates part of the hostname - so it is the
only one the role goes and asks about.

## Variables

- `database_endpoint_aws`: the AWS CLI to call. Defaults to `aws`.

Everything else comes from `group_vars/all.yml`, which reads the project
configuration: `oilscope_database_managed`, `oilscope_database_instance`,
`oilscope_aws_region`.
