# GCP module

Everything this deployment needs in Google Cloud: the VPC and its subnets,
Cloud NAT, the role-based firewall, the VMs with their service accounts, and
the Secret Manager containers with per-workload access.

## Interface

It takes the whole project configuration and nothing else of substance. The
module picks the VMs whose `cloud` resolves to `gcp`, translates every portable
token through the `catalog` the configuration carries, and creates what those
VMs need. When no VM targets this cloud it creates nothing at all - not an
empty network, not an enabled API.

`modules/aws` accepts the same variables and returns the same outputs. The root
module passes both the same value and merges what comes back without knowing
which cloud produced it.

| Input | |
| --- | --- |
| `config` | the decoded project configuration |
| `enable_bastion_ssh_bootstrap` | temporary port-22 rule for the first Ansible run |
| `secret_version_managers` | IAM members allowed to add secret versions |

| Output | |
| --- | --- |
| `region` | resolved provider region, or null when nothing was created |
| `vms` | one entry per VM: name, cloud, role, addresses, network groups, runtime identity, secret access |
| `secret_resource_names` | fully qualified secret names, never values |

## What is specific to this cloud

Firewall rules select instances by network tag, so `network_groups` here are
tag strings. The runtime identity is a service account. Egress goes through
Cloud NAT, which is attached to the workload subnet only. Public addresses work
regardless of which subnet the instance sits in, so a VM is placed by its role
rather than by whether it needs one - the AWS module cannot do that.

`templates/` holds the unused legacy cloud-init implementation, kept as-is
until the ticket that owns it removes it. The CI cloud-init schema check reads
`cloud-config.yaml.tftpl` from there.
