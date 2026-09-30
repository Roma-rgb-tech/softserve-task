locals {
  groups = {
    bastion = "Bastion host"
    k3s     = "k3s cluster node"
  }

  group_ids = { for name, group in aws_security_group.this : name => group.id }

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
      for name in local.enabled ? ["k3s-ssh"] : [] :
      name => {
        group       = "k3s", cidr_ipv4 = null, source_group = "bastion"
        from_port   = 22, to_port = 22
        description = "SSH from the bastion"
      }
    },
    {
      for port in local.enabled ? var.config.network.ui_public_ports : [] :
      "k3s-web/${port}" => {
        group       = "k3s", cidr_ipv4 = "0.0.0.0/0", source_group = null
        from_port   = tonumber(port), to_port = tonumber(port)
        description = "Public web traffic to Traefik, which runs on every node"
      }
    },
  )

  # Rules that open every protocol: between the nodes (API, etcd, kubelet,
  # flannel VXLAN), and from the subnet router, which masquerades the nodes of
  # the other clouds and the operator's tailnet device behind its own address.
  open_rules = merge(
    {
      for name in local.enabled ? ["k3s-cluster"] : [] :
      name => {
        group       = "k3s", source_group = "k3s"
        description = "Everything between the cluster nodes"
      }
    },
    {
      for name in local.enabled && local.has_bastion && local.tailnet ? ["tailnet-k3s"] : [] :
      name => {
        group       = "k3s", source_group = "bastion"
        description = "Cluster traffic from the other clouds and the operator, through the tailnet subnet router"
      }
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "open" {
  for_each = local.open_rules

  security_group_id            = local.group_ids[each.value.group]
  referenced_security_group_id = local.group_ids[each.value.source_group]
  ip_protocol                  = "-1"
  description                  = each.value.description

  tags = local.tags
}
