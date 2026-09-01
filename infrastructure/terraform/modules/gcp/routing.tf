resource "google_compute_router" "main" {
  count = local.network_count

  name    = "${local.resource_prefix}-router"
  network = google_compute_network.main[0].id
  region  = local.region
}

resource "google_compute_router_nat" "main" {
  count = local.network_count

  name   = "${local.resource_prefix}-nat"
  router = google_compute_router.main[0].name
  region = local.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.workload[0].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
