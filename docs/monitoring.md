# Monitoring

Every alert, dashboard and budget here is built from the cloud's own tools —
Cloud Monitoring and Cloud Logging on GCP, CloudWatch and AWS Budgets on AWS.
Nothing is self-hosted. That is a deliberate constraint, and it also happens to
be the cheap answer: a Prometheus and a Grafana would each need a VM, a disk, a
backup story and a way of being monitored themselves.

The two clouds are configured from the same `monitoring` block of the project
configuration, so a threshold is written once and means the same thing on both
sides.

```json
"monitoring": {
  "alert_emails": ["you@example.com"],
  "cpu_percent": 80,
  "memory_percent": 85,
  "disk_percent": 85,
  "error_log_threshold": 5,
  "budget": { "amount": 20, "currency": "USD", "thresholds": [0.5, 0.9, 1.0] }
}
```

Leave the block out and no monitoring resources are created at all — useful for
a throwaway environment, and it keeps the module honest about what it owns.

## What is watched

| | GCP | AWS |
| --- | --- | --- |
| CPU | alert policy on `compute.googleapis.com/instance/cpu/utilization` | alarm on `AWS/EC2 CPUUtilization` |
| Memory | alert policy on `agent.googleapis.com/memory/percent_used` | alarm on `CWAgent mem_used_percent` |
| Disk | alert policy on `agent.googleapis.com/disk/percent_used` | alarm on `CWAgent disk_used_percent` |
| VM availability | absence of `instance/uptime` for five minutes | `StatusCheckFailed`, missing data treated as breaching |
| 5xx responses | log-based metric over the container logs | log metric filter over the same logs |
| Spend | `google_billing_budget` | `aws_budgets_budget` |
| Overview | Cloud Monitoring dashboard | CloudWatch dashboard |

Every alert policy carries a `documentation` block and every alarm an
`alarm_description`, so the mail that arrives says what the condition means and
where to look next, rather than only which threshold was crossed.

### What the dashboard does not show

Availability and 5xx responses are watched, but they are not drawn. Both are
zero almost all of the time, and a chart that is a flat line at zero teaches a
reader to stop looking at it - while the one moment it stops being zero is
exactly the moment nobody is looking at a dashboard anyway. Those two belong to
the alerts, which arrive whether or not anyone is watching.

What remains on the dashboard is the three signals a person actually reads
while working: CPU, memory and disk.

### Availability is the absence of a signal

A VM that has crashed does not report a high value; it reports nothing. So the
GCP policy is a `condition_absent` on the uptime metric, and the AWS alarm sets
`treat_missing_data = "breaching"`. Both are the same statement: an instance
that stopped saying anything has not become healthy.

That covers the machine, not the path to it. Nothing here probes the published
site from outside. The checks that used to do it opened a TCP connection to
port 443 and closed it again, which stayed green whether the proxy answered
normally, answered with an error, or served an expired certificate — the same
statement the availability policy already makes, at the price of a second alert
to read. A probe worth keeping would request a page over HTTPS and validate the
certificate; until there is one, a working VM whose site is unreachable is not
detected here.

### Memory and disk need an agent

Neither cloud can see inside a running guest. CPU, network and instance health
come from the hypervisor; memory and disk usage have to be reported by
something running on the machine. That something is the cloud's own agent — the
Ops Agent on GCP, the CloudWatch agent on AWS — installed by the
`oilscope.platform.monitoring_agent` role.

The agent is also what ships the container logs, so the 5xx alerts depend on
it too. CPU and availability deliberately do not: they keep working on a host
where the agent has died, which is exactly when you want to hear about it.

### The 5xx alert

Docker's json-file driver writes one JSON object per line under
`/var/lib/docker/containers`. Both agents tail that glob. On GCP the Ops Agent
parses the envelope, so the application's own line arrives as `jsonPayload.log`
and the log-based metric matches a regex inside it; on AWS the envelope is left
alone and the metric filter matches the escaped text directly. Both look for
the status code an HTTP server writes right after the request line:

```
INFO: 10.10.1.14:53210 - "GET /api/prices HTTP/1.1" 500 Internal Server Error
```

The alert fires at `error_log_threshold` matches within five minutes, so a
single failed request does not wake anyone.

## Where the mail comes from

GCP creates one `email` notification channel per address and starts delivering
immediately.

AWS publishes every alarm to one SNS topic and subscribes the addresses to it.
**SNS mails each address a confirmation link first and delivers nothing until
it is clicked.** That is the one manual step in the whole setup, and it is a
property of SNS rather than a choice here. The budget is the exception: AWS
Budgets mails the addresses directly, so budget alerts arrive without any
confirmation.

## The budget

Both budgets are monthly and alert at each share of the amount listed in
`thresholds`, on actual spend.

On AWS this needs nothing extra. On GCP a budget lives on the *billing account*
rather than on the project, so it is created only when `gcp.billing_account` is
set:

```bash
gcloud billing accounts list
```

```json
"gcp": {
  "project_id": "oilscope-dev-109df1",
  "billing_account": "01ABCD-2345EF-67890A"
}
```

Without it the module creates no budget and everything else still applies —
the credentials that build a project frequently cannot see the billing account
at all, and failing the whole apply over that would be worse.

The GCP budget turns off the default IAM recipients, so its mail goes to the
same addresses as every other alert rather than to whoever happens to hold a
billing role.

## Running it

Terraform creates the alerting; the agents are installed by Ansible.

```bash
terraform apply -var=project_config_path=/absolute/path/project-config.json

ansible-playbook oilscope.platform.site \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`site.yml` installs the agents last, because the log glob has nothing in it
until the containers are running. To touch only the agents:

```bash
ansible-playbook oilscope.platform.monitoring \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`terraform output monitoring` names the dashboard and the delivery path on each
cloud in use.

## What the VMs are allowed to do

Writing a metric or a log line is a project-level permission on GCP — there is
no per-resource form of it — so each workload service account holds
`roles/monitoring.metricWriter` and `roles/logging.logWriter`. Both are
write-only: neither can read back a metric, a log entry, or anything else.

On AWS the equivalent is an inline policy rather than the managed
`CloudWatchAgentServerPolicy`, which allows publishing into any namespace and
reading every parameter in Systems Manager. The policy here allows
`cloudwatch:PutMetricData` in the `CWAgent` namespace, writes into this
project's log groups, and reading the instance's own tags. The log group itself
is created by Terraform with a retention of 30 days, so the agent is not
allowed to create one and cannot quietly start an unbounded log bill.

## A note on cost

Alerts, alarms, dashboards and budgets are free or close to it at this size.
The one thing that is: log ingestion, which both clouds bill per GiB beyond a
monthly free allowance. Retention on the AWS log group is set to 30 days for
that reason; the GCP `_Default` bucket keeps logs for 30 days out of the box.
