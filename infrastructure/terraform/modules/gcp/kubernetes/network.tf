resource "google_compute_subnetwork" "nodes" {
  count = local.count

  name          = "${local.prefix}-gke-nodes"
  network       = var.network_id
  region        = local.region
  ip_cidr_range = local.node_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = local.pod_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = local.service_cidr
  }
}

resource "google_compute_router" "nodes" {
  count = local.count

  name    = "${local.prefix}-gke-router"
  network = var.network_id
  region  = local.region
}

resource "google_compute_router_nat" "nodes" {
  count = local.count

  name   = "${local.prefix}-gke-nat"
  router = google_compute_router.nodes[0].name
  region = local.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.nodes[0].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_firewall" "control_plane_webhooks" {
  count = local.count

  name      = "${local.prefix}-gke-webhooks"
  network   = var.network_id
  direction = "INGRESS"

  source_ranges = [local.master_cidr]
  target_tags   = [local.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "9443", "10250", "10260"]
  }
}
