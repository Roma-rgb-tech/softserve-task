locals {
  cloud  = "gcp"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")
  region_token  = lookup(local.config, "default_region", "")

  region = lookup(lookup(local.config.catalog.region, local.cloud, {}), local.region_token, null)

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled = length(local.selected) > 0
  count   = local.enabled ? 1 : 0

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  network_tags = {
    bastion = "${local.resource_prefix}-bastion"
    infra   = "${local.resource_prefix}-infra"
    history = "${local.resource_prefix}-history"
    fetcher = "${local.resource_prefix}-fetcher"
    ui      = "${local.resource_prefix}-ui"
  }

  bastion_vms      = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion      = length(local.bastion_vms) > 0
  bastion_cidrs    = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_ssh_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bastion_bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_ssh_port != 22

  ui_public_ports = [for port in local.config.network.ui_public_ports : tostring(port)]

  firewall_rules = {
    "bastion-ssh" = {
      enabled       = local.has_bastion
      source_ranges = local.bastion_cidrs
      source_tags   = null
      target_tags   = [local.network_tags.bastion]
      allow         = [{ protocol = "tcp", ports = [tostring(local.bastion_ssh_port)] }]
    }

    "bastion-ssh-bootstrap" = {
      enabled       = local.has_bastion && local.bastion_bootstrap
      source_ranges = local.bastion_cidrs
      source_tags   = null
      target_tags   = [local.network_tags.bastion]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    }

    "workload-ssh" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.network_tags.bastion]
      target_tags = [
        local.network_tags.infra,
        local.network_tags.history,
        local.network_tags.fetcher,
        local.network_tags.ui,
      ]
      allow = [{ protocol = "tcp", ports = ["22"] }]
    }

    "ui-web" = {
      enabled       = local.enabled
      source_ranges = ["0.0.0.0/0"]
      source_tags   = null
      target_tags   = [local.network_tags.ui]
      allow         = [{ protocol = "tcp", ports = local.ui_public_ports }]
    }

    "history-api" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.network_tags.ui]
      target_tags   = [local.network_tags.history]
      allow         = [{ protocol = "tcp", ports = [tostring(local.config.service_ports.history_api)] }]
    }

    "postgresql" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.network_tags.fetcher, local.network_tags.history, local.network_tags.ui]
      target_tags   = [local.network_tags.infra]
      allow         = [{ protocol = "tcp", ports = [tostring(local.config.service_ports.postgresql)] }]
    }
  }

  active_rules = { for name, rule in local.firewall_rules : name => rule if rule.enabled }
}
