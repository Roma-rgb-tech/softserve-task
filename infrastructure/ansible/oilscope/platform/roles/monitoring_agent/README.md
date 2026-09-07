# Monitoring agent role

Installs the monitoring agent belonging to the cloud a host runs in, and points
it at the container logs: the Ops Agent on Compute Engine, the CloudWatch agent
on EC2. Which one is decided from the host's inventory group, so the playbook
does not have to be told.

Neither cloud reports memory or disk usage of a running VM on its own — the
hypervisor sees an opaque guest. CPU, network and instance health come from the
platform; everything measured inside the machine comes from this agent. That is
the whole reason the role exists.

It also ships every container's stdout, which is where the 5xx alerts come
from. Terraform builds a log-based metric on one side and the alert on the
other; this role is what puts the lines there in the first place.

## What lands where

| | GCP | AWS |
| --- | --- | --- |
| agent | Ops Agent | CloudWatch agent |
| memory | `agent.googleapis.com/memory/percent_used` | `CWAgent/mem_used_percent` |
| disk | `agent.googleapis.com/disk/percent_used` | `CWAgent/disk_used_percent`, root filesystem only |
| logs | Cloud Logging, `log_id("docker")` | CloudWatch Logs, `/<name_prefix>/<environment>/docker` |

Both destinations are derived from `name_prefix` and `environment` in the
project configuration — the same two values Terraform builds the log group and
the alert policies from, so the agent cannot end up writing somewhere nothing
is watching.

The Docker json-file driver wraps each line in a JSON object. On GCP the Ops
Agent parses it, so the application's own line is `jsonPayload.log`; on AWS the
envelope is left alone and the metric filter matches inside it. Both alerts
look for the status code an HTTP server writes after the request line.

## Requirements

The VM's own identity must be allowed to write telemetry. Terraform grants it:
`roles/monitoring.metricWriter` and `roles/logging.logWriter` on GCP, and on AWS
an inline policy allowing `cloudwatch:PutMetricData` in the `CWAgent` namespace
plus writes into this project's log groups. Neither grant can read anything
back.

The AWS log group is created by Terraform rather than by the agent, so that
retention is set from the start — the agent is deliberately not allowed to
create one.

## Variables

- `monitoring_agent_config_path`: path to the project configuration JSON.
  Defaults to `project_config_path`, so a play that already passes that needs
  nothing else.
- `monitoring_agent_container_logs`: glob the agent tails. Defaults to the
  Docker json-file driver's location.
- `monitoring_agent_interval`: seconds between metric samples. Default 60.
- `monitoring_agent_ops_agent_script_url`,
  `monitoring_agent_cloudwatch_package_url`: where the agents are fetched from.

## Example

```bash
ansible-playbook oilscope.platform.monitoring \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`oilscope.platform.site` runs it after the workloads, because the log glob only
has anything in it once the containers are up.

## License

GPL-2.0-or-later
