locals {
  roles = ["bastion", "infra", "history", "fetcher", "ui"]

  bastion_vms  = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion  = length(local.bastion_vms) > 0
  from_cidrs   = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_port != 22

  rules = {
    "bastion-ssh" = {
      enabled       = local.has_bastion
      source_ranges = local.from_cidrs
      source_tags   = null
      target_tags   = [local.tags.bastion]
      allow         = [{ protocol = "tcp", ports = [tostring(local.bastion_port)] }]
    }

    "bastion-ssh-bootstrap" = {
      enabled       = local.has_bastion && local.bootstrap
      source_ranges = local.from_cidrs
      source_tags   = null
      target_tags   = [local.tags.bastion]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    }

    "workload-ssh" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.tags.bastion]
      target_tags   = [local.tags.infra, local.tags.history, local.tags.fetcher, local.tags.ui]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    }

    "ui-web" = {
      enabled       = local.enabled
      source_ranges = ["0.0.0.0/0"]
      source_tags   = null
      target_tags   = [local.tags.ui]
      allow         = [{ protocol = "tcp", ports = [for p in var.config.network.ui_public_ports : tostring(p)] }]
    }

    "history-api" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.tags.ui]
      target_tags   = [local.tags.history]
      allow         = [{ protocol = "tcp", ports = [tostring(var.config.service_ports.history_api)] }]
    }

    "postgresql" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.tags.fetcher, local.tags.history, local.tags.ui]
      target_tags   = [local.tags.infra]
      allow         = [{ protocol = "tcp", ports = [tostring(var.config.service_ports.postgresql)] }]
    }
  }

  active_rules = { for name, rule in local.rules : name => rule if rule.enabled }
}
