locals {
  groups = {
    bastion = "Bastion host"
    k3s     = "k3s cluster node"
  }

  group_ids = { for name, group in azurerm_application_security_group.this : name => group.id }

  bastion_vms  = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion  = length(local.bastion_vms) > 0
  from_cidrs   = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_port != 22

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
      for name in local.enabled ? ["k3s-ssh"] : [] :
      name => {
        group = "k3s", cidr = null, source_group = "bastion"
        port  = 22
      }
    },
    {
      for port in local.enabled ? var.config.network.ui_public_ports : [] :
      "k3s-web/${port}" => {
        group = "k3s", cidr = "Internet", source_group = null
        port  = tonumber(port)
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

  # Every protocol: between the nodes (API, etcd, kubelet, flannel VXLAN), and
  # from the subnet router, which masquerades the nodes of the other clouds and
  # the operator's tailnet device behind its own address. Both sit below the
  # deny-virtual-network rule at 4000.
  open_rules = merge(
    {
      for name in local.enabled ? ["k3s-cluster"] : [] :
      name => { group = "k3s", source_group = "k3s", priority = 3800 }
    },
    {
      for name in local.enabled && local.has_bastion && local.tailnet ? ["tailnet-k3s"] : [] :
      name => { group = "k3s", source_group = "bastion", priority = 3810 }
    },
  )
}

resource "azurerm_network_security_rule" "open" {
  for_each = local.open_rules

  name                        = each.key
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vms[0].name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"

  source_application_security_group_ids      = [local.group_ids[each.value.source_group]]
  destination_application_security_group_ids = [local.group_ids[each.value.group]]

  lifecycle {
    replace_triggered_by = [azurerm_application_security_group.this]
  }
}
