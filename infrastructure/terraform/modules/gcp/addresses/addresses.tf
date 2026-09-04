resource "google_compute_address" "public" {
  for_each = local.public_vms

  name   = "${local.prefix}-${each.key}-ip"
  region = local.region
}
