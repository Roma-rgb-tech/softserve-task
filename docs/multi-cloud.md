# Deploying to more than one cloud

One configuration file describes one deployment in one cloud. The same stack,
the same five roles and the same playbooks go up in GCP or in AWS depending on
a single field. Nothing is split across clouds: there is no network between
them, and building one would be a larger job than the portability it buys.

```json
{ "cloud": "gcp", "location": "us-east", ... }
```

Change `cloud` to `aws`, point `-backend-config` at the other state, and the
same `terraform apply` builds the equivalent stack in Amazon.

## Where the abstraction lives

Two places, and neither of them is inside a module.

**The configuration speaks in intent.** `size: micro`, `os: ubuntu-26.04`,
`boot_disk.type: balanced`, `location: us-east`. None of those strings is a
provider identifier, and none of them changes with the cloud.

**The root module translates.** `catalog.tf` holds one table per translatable
concept, keyed by cloud:

| Portable token | GCP | AWS |
| --- | --- | --- |
| `size: micro` | `e2-micro` | `t3.micro` |
| `boot_disk.type: balanced` | `pd-balanced` | `gp3` |
| `location: us-east` | `us-east1` / `us-east1-b` | `us-east-1` / `us-east-1a` |

The table lives in the repository rather than in a configuration file on
purpose: a configuration picks from a fixed menu, and the menu is owned by the
team. Adding a cloud is adding a column, not editing any deployment.

`validation.tf` checks every token before a provider is called, so a typo names
itself and lists what was allowed instead of surfacing as `Invalid index` from
somewhere inside a module.

## What cannot be translated

Some things are not the same concept under two names. Compute Engine network
tags and EC2 security groups both restrict traffic, but one is a string on an
instance and the other is a resource referenced by ID. A lookup table cannot
bridge that, and pretending otherwise produces the worst version of both.

Those live in the modules, and the abstraction is the **module interface**:
`modules/gcp/vm` and `modules/aws/vm` accept the same variables and return the
same outputs. The root passes `network_groups` and reads `runtime_identity`
without knowing whether it just handed over a network tag or a security group
ID, an service-account email or an IAM role name.

Anything genuinely cloud-specific sits in its own configuration section - `gcp`
for the project ID, `aws` for the account ID - so it never pretends to be
portable.

## What is not hardcoded at all

An AMI ID differs per region and changes with every Canonical release. Putting
one in a configuration file or a lookup table guarantees a break within weeks,
so the portable `os` token resolves to a **name pattern** and the AWS module
looks the current AMI up with a data source. GCP resolves the same token to an
image family, which is the same idea served by the provider.

## Choosing which modules run

Every module is declared once and receives an empty input when its cloud is not
the active one:

```hcl
module "aws_vm" {
  source   = "./modules/aws/vm"
  for_each = local.aws_vms       # {} unless cloud is aws
}
```

An empty map creates nothing, and the alternative - `count` - would force a
`[0]` index into every reference downstream. Both providers are declared and
the unused one performs no API call, because Terraform only contacts a provider
that owns a resource in the plan.

## What differs in practice

**Egress.** The GCP stack reaches the internet from its private subnet through
Cloud NAT. The AWS module uses a NAT gateway, which is billed per hour from the
moment it exists and is **not covered by the free tier** - roughly $33 a month
before any traffic. Destroy an AWS environment you are not using.

**SSH accounts.** Compute Engine takes public keys through instance metadata.
EC2 has no equivalent channel, so the AWS module writes a minimal cloud-init
document that creates the accounts and installs the keys, and nothing else.
Docker and the application remain Ansible's job in both clouds.

**Reading secrets.** Both clouds grant a workload access to its own secrets and
nothing more, and in both the VM proves its identity to the metadata service
rather than holding a key file. The mechanism differs: GCP's metadata server
returns a bearer token that works directly against the Secret Manager API,
while Secrets Manager requires a SigV4 signature on every request, so the AWS
path signs through the AWS CLI using the instance profile. Which endpoints a
host uses comes from `inventory/group_vars/cloud_<name>.yml`, so adding a cloud
is adding a file rather than another condition inside the role.

**Enabling services.** `apis.tf` exists only for GCP. AWS services are
available to an account without being enabled per project.

## Inventory

`inventory/` holds one file per cloud. Pass the **directory** as the inventory
and Ansible merges them; a plugin with no credentials or no matching instances
contributes no hosts.

```sh
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/ \
  -e project_config_path=/absolute/path/project-config.json
```

The group names and the composed variable names are identical in both files by
contract. GCP builds groups from instance labels and AWS from instance tags,
but a playbook targets `database` either way, and the `ui` role resolves its
peers through `internal_ip` either way.
