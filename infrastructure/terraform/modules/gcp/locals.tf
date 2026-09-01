locals {
  cloud  = "gcp"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")
  region_token  = lookup(local.config, "default_region", "")

  region = lookup(lookup(local.config.catalog.region, local.cloud, {}), local.region_token, null)
  zone   = lookup(lookup(local.config.catalog.zone, local.cloud, {}), local.region_token, null)

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled       = length(local.selected) > 0
  network_count = local.enabled ? 1 : 0

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud
    },
    local.config.common_labels,
  )

  network_tags = {
    bastion = "${local.resource_prefix}-bastion"
    infra   = "${local.resource_prefix}-infra"
    history = "${local.resource_prefix}-history"
    fetcher = "${local.resource_prefix}-fetcher"
    ui      = "${local.resource_prefix}-ui"
  }

  vms = {
    for name, vm in local.selected : name => merge(vm, {
      machine_type = lookup(lookup(local.config.catalog.size, local.cloud, {}), vm.size, null)
      disk_type    = lookup(lookup(local.config.catalog.disk_type, local.cloud, {}), vm.boot_disk.type, null)
      image        = lookup(lookup(local.config.catalog.os, local.cloud, {}), vm.os, null)

      public_subnet = vm.role == "bastion" || vm.assign_public_ip

      tags = [for tag in vm.network_tags : local.network_tags[tag]]

      labels = merge(local.labels, lookup(vm, "labels", {}), { role = vm.role })
    })
  }

  public_vms = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  bastion_vms      = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion      = length(local.bastion_vms) > 0
  bastion_cidrs    = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_ssh_port = one([for vm in local.bastion_vms : vm.ssh_port])

  ui_public_ports = [for port in local.config.network.ui_public_ports : tostring(port)]

  secret_reading_vms = {
    for name, vm in local.vms : name => vm
    if vm.role != "bastion" && length(vm.secret_mappings) > 0
  }

  secret_ids = distinct(flatten([
    for name, vm in local.secret_reading_vms : values(vm.secret_mappings)
  ]))

  workload_secret_pairs = flatten([
    for name, vm in local.secret_reading_vms : [
      for secret_id in distinct(values(vm.secret_mappings)) : {
        vm_name   = name
        secret_id = secret_id
      }
    ]
  ])

  secret_version_writers = {
    for pair in setproduct(sort(local.secret_ids), var.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }

  required_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}
