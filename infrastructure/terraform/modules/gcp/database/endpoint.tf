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

resource "google_dns_managed_zone" "database" {
  count = local.enabled

  name        = "${local.prefix}-database"
  dns_name    = google_sql_database_instance.main[0].dns_name
  description = "Private Service Connect endpoint of the managed database"
  visibility  = "private"
  labels      = local.labels

  private_visibility_config {
    networks {
      network_url = var.network_id
    }
  }
}

resource "google_dns_record_set" "database" {
  count = local.enabled

  name         = google_sql_database_instance.main[0].dns_name
  managed_zone = google_dns_managed_zone.database[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.endpoint[0].address]
}
