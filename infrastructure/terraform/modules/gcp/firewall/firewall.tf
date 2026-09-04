resource "google_compute_firewall" "rules" {
  for_each = local.active_rules

  name    = "${local.prefix}-allow-${each.key}"
  network = var.network_id

  source_ranges = each.value.source_ranges
  source_tags   = each.value.source_tags
  target_tags   = each.value.target_tags

  dynamic "allow" {
    for_each = each.value.allow

    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }
}
