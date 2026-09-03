locals {
  cloud  = "aws"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")
  location      = lookup(local.config, "location", "")

  region = lookup(lookup(local.config.catalog.region, local.cloud, {}), local.location, null)
  zone   = lookup(lookup(local.config.catalog.zone, local.cloud, {}), local.location, null)

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled       = length(local.selected) > 0
  network_count = local.enabled ? 1 : 0

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  tags = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
    },
    local.config.common_labels,
  )

  iops_required = ["io1", "io2"]

  # The route to the internet belongs to the subnet here, so a VM that needs a
  # public address belongs in the public subnet rather than where its role
  # would otherwise place it.
  vms = {
    for name, vm in local.selected : name => merge(vm, {
      machine_type = lookup(lookup(local.config.catalog.size, local.cloud, {}), vm.size, null)
      disk_type    = lookup(lookup(local.config.catalog.disk_type, local.cloud, {}), vm.boot_disk.type, null)
      image        = lookup(lookup(local.config.catalog.os, local.cloud, {}), vm.os, null)

      public_subnet = vm.role == "bastion" || vm.assign_public_ip

      subnet_cidr = (vm.role == "bastion" || vm.assign_public_ip
        ? local.config.network.management_subnet_cidr
      : local.config.network.workload_subnet_cidr)

      tags = merge(local.tags, lookup(vm, "labels", {}), { role = vm.role })
    })
  }

  public_vms = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  bastion_vms      = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion      = length(local.bastion_vms) > 0
  bastion_cidrs    = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_ssh_port = one([for vm in local.bastion_vms : vm.ssh_port])

  ui_public_ports = [for port in local.config.network.ui_public_ports : tostring(port)]

  workload_groups = {
    infra   = one(aws_security_group.infra[*].id)
    history = one(aws_security_group.history[*].id)
    fetcher = one(aws_security_group.fetcher[*].id)
    ui      = one(aws_security_group.ui[*].id)
  }

  security_groups = local.enabled ? merge(local.workload_groups, {
    bastion = one(aws_security_group.bastion[*].id)
  }) : {}

  secret_reading_vms = {
    for name, vm in local.vms : name => vm
    if vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  secret_ids = distinct(flatten([
    for name, vm in local.secret_reading_vms : values(vm.secret_mappings)
  ]))
}
