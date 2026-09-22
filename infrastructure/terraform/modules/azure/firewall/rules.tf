locals {
  groups = {
    bastion = "Bastion host"
    infra   = "Database workload"
    history = "History workload"
    fetcher = "Fetcher workload"
    ui      = "UI workload"
  }

  workloads = ["infra", "history", "fetcher", "ui"]
  group_ids = { for name, group in azurerm_application_security_group.this : name => group.id }

  bastion_vms  = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion  = length(local.bastion_vms) > 0
  from_cidrs   = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_port != 22

  ports      = var.config.service_ports
  amqp_port  = lookup(var.config.service_ports, "amqp", 5672)
  redis_port = lookup(var.config.service_ports, "redis", 6379)

  ingress_rules = merge(
    {
      for cidr in local.has_bastion ? local.from_cidrs : [] :
      "bastion-ssh/${cidr}" => {
        group = "bastion", cidr = cidr, source_group = null
        port  = local.bastion_port
      }
    },
    {
      for cidr in local.has_bastion && local.bootstrap ? local.from_cidrs : [] :
      "bastion-ssh-bootstrap/${cidr}" => {
        group = "bastion", cidr = cidr, source_group = null
        port  = 22
      }
    },
    {
      for role in local.enabled ? local.workloads : [] :
      "workload-ssh/${role}" => {
        group = role, cidr = null, source_group = "bastion"
        port  = 22
      }
    },
    {
      for port in local.enabled ? var.config.network.ui_public_ports : [] :
      "ui-web/${port}" => {
        group = "ui", cidr = "Internet", source_group = null
        port  = tonumber(port)
      }
    },
    {
      for role in local.enabled && !local.managed ? ["fetcher", "history", "ui"] : [] :
      "postgresql/${role}" => {
        group = "infra", cidr = null, source_group = role
        port  = local.ports.postgresql
      }
    },
    {
      for role in local.enabled && local.managed ? ["fetcher", "history"] : [] :
      "amqp/${role}" => {
        group = "infra", cidr = null, source_group = role
        port  = local.amqp_port
      }
    },
    {
      for role in local.enabled && local.cached ? ["ui"] : [] :
      "redis/${role}" => {
        group = "infra", cidr = null, source_group = role
        port  = local.redis_port
      }
    },
    {
      for name in local.enabled ? ["history-api"] : [] :
      name => {
        group = "history", cidr = null, source_group = "ui"
        port  = local.ports.history_api
      }
    },
  )

  rule_names = sort(keys(local.ingress_rules))

  prioritized = {
    for index, name in local.rule_names : name => merge(local.ingress_rules[name], {
      priority = 100 + index * 10
      name     = replace(replace(replace(name, "/", "-"), ".", "-"), ":", "-")
    })
  }
}
