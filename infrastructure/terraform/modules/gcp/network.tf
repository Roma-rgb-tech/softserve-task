resource "google_compute_network" "main" {
  count = local.network_count

  name = "${local.resource_prefix}-vpc"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "management" {
  count = local.network_count

  name          = "${local.resource_prefix}-management"
  network       = google_compute_network.main[0].id
  region        = local.region
  ip_cidr_range = local.config.network.management_subnet_cidr
}

resource "google_compute_subnetwork" "workload" {
  count = local.network_count

  name          = "${local.resource_prefix}-workload"
  network       = google_compute_network.main[0].id
  region        = local.region
  ip_cidr_range = local.config.network.workload_subnet_cidr

  private_ip_google_access = true
}
