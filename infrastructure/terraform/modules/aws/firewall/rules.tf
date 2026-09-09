locals {
  groups = {
    bastion = "Bastion host"
    infra   = "Database workload"
    history = "History workload"
    fetcher = "Fetcher workload"
    ui      = "UI workload"
  }

  workloads = ["infra", "history", "fetcher", "ui"]
  group_ids = { for name, group in aws_security_group.this : name => group.id }

  bastion_vms  = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion  = length(local.bastion_vms) > 0
  from_cidrs   = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_port != 22

  ports     = var.config.service_ports
  amqp_port = lookup(var.config.service_ports, "amqp", 5672)

  ingress_rules = merge(
    {
      for cidr in local.has_bastion ? local.from_cidrs : [] :
      "bastion-ssh/${cidr}" => {
        group       = "bastion", cidr_ipv4 = cidr, source_group = null
        from_port   = local.bastion_port, to_port = local.bastion_port
        description = "Operator SSH to the bastion"
      }
    },
    {
      for cidr in local.has_bastion && local.bootstrap ? local.from_cidrs : [] :
      "bastion-ssh-bootstrap/${cidr}" => {
        group       = "bastion", cidr_ipv4 = cidr, source_group = null
        from_port   = 22, to_port = 22
        description = "Temporary bootstrap SSH to the bastion"
      }
    },
    {
      for role in local.enabled ? local.workloads : [] :
      "workload-ssh/${role}" => {
        group       = role, cidr_ipv4 = null, source_group = "bastion"
        from_port   = 22, to_port = 22
        description = "SSH from the bastion"
      }
    },
    {
      for port in local.enabled ? var.config.network.ui_public_ports : [] :
      "ui-web/${port}" => {
        group       = "ui", cidr_ipv4 = "0.0.0.0/0", source_group = null
        from_port   = tonumber(port), to_port = tonumber(port)
        description = "Public HTTPS to the UI"
      }
    },
    {
      for role in local.enabled && !local.managed ? ["fetcher", "history", "ui"] : [] :
      "postgresql/${role}" => {
        group       = "infra", cidr_ipv4 = null, source_group = role
        from_port   = local.ports.postgresql, to_port = local.ports.postgresql
        description = "PostgreSQL from ${role}"
      }
    },
    {
      for role in local.enabled && local.managed ? ["fetcher", "history"] : [] :
      "amqp/${role}" => {
        group       = "infra", cidr_ipv4 = null, source_group = role
        from_port   = local.amqp_port, to_port = local.amqp_port
        description = "AMQP from ${role}"
      }
    },
    {
      for name in local.enabled ? ["history-api"] : [] :
      name => {
        group       = "history", cidr_ipv4 = null, source_group = "ui"
        from_port   = local.ports.history_api, to_port = local.ports.history_api
        description = "History API from the UI"
      }
    },
  )
}
