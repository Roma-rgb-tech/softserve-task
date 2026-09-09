resource "google_compute_address" "endpoint" {
  count = local.enabled

  name         = "${local.prefix}-database-endpoint"
  region       = local.region
  subnetwork   = var.subnet_id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "endpoint" {
  count = local.enabled

  name                  = "${local.prefix}-database-endpoint"
  region                = local.region
  network               = var.network_id
  ip_address            = google_compute_address.endpoint[0].id
  target                = google_sql_database_instance.main[0].psc_service_attachment_link
  load_balancing_scheme = ""

  allow_psc_global_access = false
}
