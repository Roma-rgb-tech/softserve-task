# Deploying to more than one cloud

The same stack, the same five roles and the same playbooks go up in GCP or in
AWS. Which cloud is a field in the project configuration, not a property of the
code.

```json
{ "default_cloud": "gcp", "default_region": "us-east", ... }
```

`default_cloud` covers every VM. A VM may name a different one for itself:

```json
"vms": {
  "bastion": { "cloud": "aws", ... },
  "infra":   { ... }
}
```

The second form exists so the mechanism does not assume one cloud per
deployment. Splitting an application across clouds needs a network between
them, which this project does not have, so in practice every VM usually takes
the default. What the per-VM field buys is a VM that genuinely belongs
elsewhere - something reaching the service from outside, for instance.

## Where the abstraction lives

**The configuration speaks in intent.** `size: micro`, `os: ubuntu-26.04`,
`boot_disk.type: balanced`, `location: us-east`. None of those strings is a
provider identifier, and none of them changes with the cloud.

**The configuration also carries the translation.** A `catalog` block holds one
table per translatable concept, keyed by cloud:

| Portable token | GCP | AWS |
| --- | --- | --- |
| `size: micro` | `e2-micro` | `t3.micro` |
| `boot_disk.type: balanced` | `pd-balanced` | `gp3` |
| `boot_disk.type: ssd` | `pd-ssd` | `io2` |
| `location: us-east` | `us-east1` / `us-east1-b` | `us-east-1` / `us-east-1a` |

It lives in the project configuration rather than in Terraform on purpose. The
configuration file is the single source of truth for the whole deployment, and
anything that reads it - the Ansible inventory plugin today, a reporting or
cost tool tomorrow - resolves the same values without Terraform having to
export them. A table kept in `.tf` would be readable by Terraform alone.

**The modules resolve it.** Each cloud module picks the VMs that target it,
looks every token up in the catalog, and creates what those VMs need. The root
module holds no translation, no filtering and no per-cloud branching.

## What cannot be translated

Some things are not the same concept under two names. Compute Engine network
tags and EC2 security groups both restrict traffic, but one is a string on an
instance and the other is a resource referenced by ID. A lookup table cannot
bridge that, and pretending otherwise produces the worst version of both.

Those live in the modules, and the abstraction is the **module interface**:
`modules/gcp` and `modules/aws` accept the same variables and return the same
outputs. The root hands each of them the whole configuration and merges the
`vms` map that comes back, without knowing whether `network_groups` holds
network tags or security group IDs, or whether `runtime_identity` is a
service-account email or an IAM role name.

## How the modules are laid out

There is no per-cloud wrapper. Every module is called from the root and receives
the whole configuration:

```
modules/gcp/base      the APIs Compute Engine, IAM and Secret Manager need
modules/gcp/network   network, routing, firewall
modules/gcp/vm        instances, runtime identities, public addresses
modules/gcp/secrets   secret containers and the access bindings
modules/aws/network   VPC, subnets, routing, security groups
modules/aws/vm        instances, runtime identities, key pair, elastic IPs
modules/aws/secrets   secret containers and the access policies
```

`modules/aws` has no `base`: AWS has no service to switch on.

**Each module decides for itself.** None of them is given a flag saying whether
this cloud is in use - every one reads `config.vms`, selects the VMs that target
its cloud, and creates nothing when that set is empty:

```hcl
selected = { for name, vm in config.vms : name => vm
             if lookup(vm, "cloud", default_cloud) == "aws" }

enabled = length(selected) > 0
```

The root passes data between them only where a dependency is real: subnet and
group identifiers from `network` into `vm`, runtime identities from `vm` into
`secrets`. Nothing flows back.

The alternative - one wrapper per cloud calling private submodules - keeps the
root shorter but makes every module reachable only through its wrapper. Flat
modules stay reusable on their own, and `terraform state list` reads as a list
of named things rather than a nest.

**Policy becomes data.** Firewall rules are not six near-identical resources any
more; they are a map in the network module's `locals.tf` that one resource
renders with `for_each` and a `dynamic` block:

```hcl
"history-api" = {
  enabled     = local.enabled
  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]
  allow       = [{ protocol = "tcp", ports = [tostring(...history_api)] }]
}
```

Adding a rule is a map entry, and both clouds describe rules in the same shape
even though one renders them into `google_compute_firewall` and the other into
security group rules. The AWS route tables use `dynamic "route"` for the same
reason: the two tables differ only in which gateway the default route names.

## Boot content the configuration carries

A VM may name its own first-boot content:

```json
"bastion": {
  "ssh_bootstrap": true,
  "ci": { "startup_script": "#!/bin/bash
..." }
}
```

`ci.startup_script` becomes instance metadata on GCP and user data on AWS, so a
machine can configure itself before anything connects to it. `ssh_bootstrap`
opens port 22 for the first deployment only, while the final sshd policy is
installed; both live in the configuration rather than in a command-line
variable, because they describe an environment, not an invocation.

The only variable the root still declares is `project_config_path`.

## What is not hardcoded at all

An AMI ID differs per region and changes with every Canonical release. Putting
one in a configuration file or a lookup table guarantees a break within weeks,
so the portable `os` token resolves to a **name pattern** and the AWS module
looks the current AMI up with a data source. GCP resolves the same token to an
image family, which is the same idea served by the provider.

## Which resources appear

Both modules are always called; each one decides for itself whether it has work
to do. A module whose cloud no VM targets creates nothing - no network, no
enabled API, no secret container:

```hcl
selected = { for name, vm in config.vms : name => vm
             if lookup(vm, "cloud", default_cloud) == "aws" }

enabled = length(selected) > 0
```

Instances and secrets come from `for_each` over `selected`, so an empty map
simply produces nothing. The shared network resources take `count` from the
same fact. Both providers are declared, and the unused one performs no API
call, because Terraform only contacts a provider that owns a resource in the
plan.

## Moving an existing state

The module layout changed: what used to be `module.network` and
`module.vm["ui"]` is now `module.gcp` with resources keyed inside it. Terraform
cannot express that as `moved` blocks, because a `moved` target may not carry a
computed key. An existing environment therefore needs its state moved by hand
once:

```sh
terraform state mv 'module.network.google_compute_network.main' \
                   'module.gcp_network.google_compute_network.main[0]'

for vm in bastion infra history fetcher ui; do
  terraform state mv "module.vm[\"$vm\"].google_compute_instance.workload" \
                     "module.gcp_vm.google_compute_instance.workload[\"$vm\"]"
done
```

An empty state needs none of this.

## Inventory

`oilscope.platform.oilscope` reads the same project configuration, works out
which clouds it declares, and delegates to the upstream plugin of each one. The
inventory file is the whole configuration:

```yaml
plugin: oilscope.platform.oilscope
project_config_path: /absolute/path/project-config.json
```

A cloud nothing targets is never contacted, so it needs no credentials.

Group names and composed variable names are identical whichever cloud a host
came from. GCP builds groups from instance labels and AWS from instance tags,
but a playbook targets `database` either way, and the `ui` role resolves its
peers through `internal_ip` either way. Every host also carries
`oilscope_cloud` and joins `cloud_gcp` or `cloud_aws`, which is how a role
picks a provider-specific path without a playbook having to say which cloud it
is running against.

## What differs in practice

**Egress.** The GCP stack reaches the internet from its private subnet through
Cloud NAT. The AWS module uses a NAT gateway, which is billed per hour from the
moment it exists and is **not covered by the free tier** - roughly $33 a month
before any traffic. Destroy an AWS environment you are not using.

**Where a public VM sits.** In AWS the route to the internet belongs to the
subnet, so an Elastic IP on an instance in the NAT-routed subnet accepts no
inbound traffic - `apply` succeeds and the host is simply unreachable. GCP has
no such coupling, but both modules follow the same rule anyway: a VM that asks
for a public address goes in the management subnet. Making GCP behave like the
stricter cloud costs nothing and buys the thing this whole change is about -
**one configuration file that works in either cloud**. Were the rule different
per cloud, `ui.internal_ip` would have to differ too, and switching clouds
would mean editing addresses rather than one line.

**SSH accounts.** Compute Engine takes public keys through instance metadata and
creates the named accounts from them. EC2 has no equivalent channel: it installs
a single key pair into the image's default account, `ubuntu` on Canonical
images. The AWS module therefore registers one `aws_key_pair` from the first
entry of `ssh_users`, and `group_vars/cloud_aws.yml` sets `ansible_user` to that
default account. This is the one place where the connection differs per cloud.

**Reading secrets.** Both clouds grant a workload access to its own secrets and
nothing more, and in both the VM proves its identity to the metadata service
rather than holding a key file. The mechanism differs: GCP's metadata server
returns a bearer token that works directly against the Secret Manager API,
while Secrets Manager requires a SigV4 signature on every request, so the AWS
path signs through the AWS CLI using the instance profile.

**Writing secret values.** The `secret_versions` role runs on the controller,
not on a VM, so it takes the cloud from the configuration rather than from a
host fact: a container is written wherever the workloads that read it live. The
payload reaches `gcloud` through `--data-file=-` and the AWS CLI through
`--secret-string file:///dev/stdin`, so in neither case does a value become a
command argument. Every value is checked before the first write, so a run
either updates the whole catalog or changes nothing.

**Enabling services.** `apis.tf` exists only for GCP. AWS services are
available to an account without being enabled per project.

**State.** The backend stays GCS for both. A bucket is a bucket, and one state
store for every environment is simpler than one per cloud; the AWS deployment
uses its own prefix.
