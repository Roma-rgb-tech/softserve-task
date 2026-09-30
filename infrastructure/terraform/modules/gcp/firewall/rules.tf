locals {
  roles = ["bastion", "k3s"]

  bastion_vms  = [for name, vm in local.selected : vm if vm.role == "bastion"]
  has_bastion  = length(local.bastion_vms) > 0
  from_cidrs   = flatten([for vm in local.bastion_vms : vm.allowed_cidrs])
  bastion_port = one([for vm in local.bastion_vms : vm.ssh_port])

  bootstrap = anytrue([
    for vm in local.bastion_vms : lookup(vm, "ssh_bootstrap", false)
  ]) && local.bastion_port != 22

  # Everything a node speaks, for the rules between the nodes themselves and for
  # what the subnet router forwards to them: the API (6443), etcd (2379-2380),
  # the kubelet (10250), flannel VXLAN (8472/udp) and ICMP for path MTU.
  all_traffic = [{ protocol = "tcp", ports = null }, { protocol = "udp", ports = null }, { protocol = "icmp", ports = null }]

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

    "k3s-ssh" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.tags.bastion]
      target_tags   = [local.tags.k3s]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    }

    # Traefik runs on every node, so any node with a public address serves the
    # site. The API server, the kubelet and etcd stay private.
    "k3s-web" = {
      enabled       = local.enabled
      source_ranges = ["0.0.0.0/0"]
      source_tags   = null
      target_tags   = [local.tags.k3s]
      allow         = [{ protocol = "tcp", ports = [for p in var.config.network.ui_public_ports : tostring(p)] }]
    }

    "k3s-cluster" = {
      enabled       = local.enabled
      source_ranges = null
      source_tags   = [local.tags.k3s]
      target_tags   = [local.tags.k3s]
      allow         = local.all_traffic
    }
  }

  tailnet_rules = {
    "tailnet-direct" = {
      enabled       = local.has_bastion && local.tailnet
      source_ranges = ["0.0.0.0/0"]
      source_tags   = null
      target_tags   = [local.tags.bastion]
      allow         = [{ protocol = "udp", ports = ["41641"] }]
    }

    "tailnet-forward" = {
      enabled       = local.has_bastion && local.tailnet
      source_ranges = [var.config.network.management_subnet_cidr, var.config.network.workload_subnet_cidr]
      source_tags   = null
      target_tags   = [local.tags.bastion]
      allow         = local.all_traffic
    }

    # The subnet router masquerades what it forwards, so nodes in the other
    # clouds and the operator's own tailnet device (kubectl, Helm, Headlamp)
    # all arrive from the bastion's address.
    "tailnet-k3s" = {
      enabled       = local.has_bastion && local.tailnet
      source_ranges = null
      source_tags   = [local.tags.bastion]
      target_tags   = [local.tags.k3s]
      allow         = local.all_traffic
    }
  }

  active_rules = { for name, rule in merge(local.rules, local.tailnet_rules) : name => rule if rule.enabled }
}
