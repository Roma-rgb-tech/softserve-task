resource "google_compute_router" "main" {
  count = local.count

  name    = "${local.prefix}-router"
  network = var.network_id
  region  = local.region
}

resource "google_compute_router_nat" "main" {
  count = local.count

  name   = "${local.prefix}-nat"
  router = google_compute_router.main[0].name
  region = local.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = var.workload_subnet_id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
