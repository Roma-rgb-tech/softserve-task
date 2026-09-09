resource "google_compute_network" "main" {
  count = local.count

  name = "${local.prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "management" {
  count = local.count

  name          = "${local.prefix}-management"
  network       = google_compute_network.main[0].id
  region        = local.region
  ip_cidr_range = var.config.network.management_subnet_cidr
}

resource "google_compute_subnetwork" "workload" {
  count = local.count

  name          = "${local.prefix}-workload"
  network       = google_compute_network.main[0].id
  region        = local.region
  ip_cidr_range = var.config.network.workload_subnet_cidr

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "database" {
  count = local.database_count

  name          = "${local.prefix}-database"
  network       = google_compute_network.main[0].id
  region        = local.region
  ip_cidr_range = local.database_cidrs[0]
}
