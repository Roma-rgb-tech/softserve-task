# AWS module

The AWS half of the deployment: VPC, a public management subnet and a private
workload subnet, NAT gateway, five security groups, the EC2 instances with
their IAM roles, and the Secrets Manager containers with per-workload access.

## Interface

Identical to `modules/gcp` - same variables, same outputs, same behaviour when
no VM targets this cloud. Two extra variables carry defaults and are not part
of the shared contract: `image_owner` and `boot_disk_iops`.

## What is specific to this cloud

Security groups replace network tags: `network_groups` here are group IDs that
rules reference by identity rather than by string. The runtime identity is an
IAM role with an instance profile. Egress is denied unless stated, so the
module writes the rules that GCP gets from its implied allow-egress.

**The route to the internet belongs to the subnet.** An Elastic IP on an
instance in the NAT-routed subnet accepts no inbound traffic - `apply` succeeds
and the host is unreachable. Any VM that asks for a public address is therefore
placed in the management subnet, which is what the `public_subnet` local
decides. AWS also reserves the first four addresses of every subnet, and a
precondition rejects an `internal_ip` that lands on one.

The AMI is never pinned: the portable `os` token resolves to a name pattern and
a data source finds the current image, because AMI IDs differ per region and
change with every Canonical release.

`boot_disk_iops` exists because AWS refuses io1 and io2 volumes that do not
state their IOPS - a requirement `terraform validate` cannot see, since the
field is optional in the provider schema.
