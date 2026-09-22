resource "google_compute_route" "remote" {
  for_each = local.enabled ? local.remote_cidrs : {}

  name              = "${local.prefix}-to-${each.key}"
  network           = var.network_id
  dest_range        = each.value
  next_hop_instance = var.next_hop
  priority          = 900
  description       = "The ${each.key} network, reached through the bastion's tailnet subnet router"
}
