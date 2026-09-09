resource "google_compute_disk" "extra" {
  for_each = local.extra_disks

  name   = "${local.prefix}-${each.value.vm}-${each.value.name}"
  zone   = local.zone
  type   = each.value.disk_type
  size   = each.value.size_gb
  labels = local.vms[each.value.vm].labels

  lifecycle {
    precondition {
      condition     = each.value.disk_type != null
      error_message = "The catalog has no gcp disk_type mapping for ${each.value.type}, asked for by disk ${each.value.name} on ${each.value.vm}."
    }
  }
}
