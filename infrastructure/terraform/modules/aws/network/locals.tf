locals {
  cloud  = "aws"
  config = var.config

  default_cloud = lookup(local.config, "default_cloud", "")
  region_token  = lookup(local.config, "default_region", "")

  zone = lookup(lookup(local.config.catalog.zone, local.cloud, {}), local.region_token, null)

  selected = {
    for name, vm in local.config.vms : name => vm
    if lookup(vm, "cloud", local.default_cloud) == local.cloud
  }

  enabled = length(local.selected) > 0
  count   = local.enabled ? 1 : 0

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

  vpc_id = one(aws_vpc.main[*].id)

  subnets = {
    for name, id in {
      management = one(aws_subnet.management[*].id)
      workload   = one(aws_subnet.workload[*].id)
    } : name => id if id != null
  }

  security_group_descriptions = {
    bastion = "Bastion host"
    infra   = "Database workload"
    history = "History workload"
    fetcher = "Fetcher workload"
    ui      = "UI workload"
  }

  workload_roles = ["infra", "history", "fetcher", "ui"]

  group_ids = { for name, group in aws_security_group.this : name => group.id }

  bastion_vms      = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion      = length(local.bastion_vms) > 0
  bastion_cidrs    = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_ssh_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bastion_bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_ssh_port != 22

  ui_public_ports = [for port in local.config.network.ui_public_ports : tostring(port)]

  bastion_ssh_rules = {
    for cidr in local.has_bastion ? local.bastion_cidrs : [] :
    "bastion-ssh/${cidr}" => {
      group        = "bastion"
      cidr_ipv4    = cidr
      source_group = null
      from_port    = local.bastion_ssh_port
      to_port      = local.bastion_ssh_port
      description  = "Operator SSH to the bastion"
    }
  }

  bastion_bootstrap_rules = {
    for cidr in local.has_bastion && local.bastion_bootstrap ? local.bastion_cidrs : [] :
    "bastion-ssh-bootstrap/${cidr}" => {
      group        = "bastion"
      cidr_ipv4    = cidr
      source_group = null
      from_port    = 22
      to_port      = 22
      description  = "Temporary bootstrap SSH to the bastion"
    }
  }

  workload_ssh_rules = {
    for role in local.enabled ? local.workload_roles : [] :
    "workload-ssh/${role}" => {
      group        = role
      cidr_ipv4    = null
      source_group = "bastion"
      from_port    = 22
      to_port      = 22
      description  = "SSH from the bastion"
    }
  }

  ui_web_rules = {
    for port in local.enabled ? local.ui_public_ports : [] :
    "ui-web/${port}" => {
      group        = "ui"
      cidr_ipv4    = "0.0.0.0/0"
      source_group = null
      from_port    = tonumber(port)
      to_port      = tonumber(port)
      description  = "Public HTTPS to the UI"
    }
  }

  postgresql_rules = {
    for role in local.enabled ? ["fetcher", "history", "ui"] : [] :
    "postgresql/${role}" => {
      group        = "infra"
      cidr_ipv4    = null
      source_group = role
      from_port    = local.config.service_ports.postgresql
      to_port      = local.config.service_ports.postgresql
      description  = "PostgreSQL from ${role}"
    }
  }

  history_api_rules = {
    for name in local.enabled ? ["history-api"] : [] :
    name => {
      group        = "history"
      cidr_ipv4    = null
      source_group = "ui"
      from_port    = local.config.service_ports.history_api
      to_port      = local.config.service_ports.history_api
      description  = "History API from the UI"
    }
  }

  ingress_rules = merge(
    local.bastion_ssh_rules,
    local.bastion_bootstrap_rules,
    local.workload_ssh_rules,
    local.ui_web_rules,
    local.postgresql_rules,
    local.history_api_rules,
  )

  route_tables = {
    for name, table in {
      management = {
        subnet_id = one(aws_subnet.management[*].id)
        routes = [{
          cidr_block     = "0.0.0.0/0"
          gateway_id     = one(aws_internet_gateway.main[*].id)
          nat_gateway_id = null
        }]
      }
      workload = {
        subnet_id = one(aws_subnet.workload[*].id)
        routes = [{
          cidr_block     = "0.0.0.0/0"
          gateway_id     = null
          nat_gateway_id = one(aws_nat_gateway.main[*].id)
        }]
      }
    } : name => table if local.enabled
  }
}
