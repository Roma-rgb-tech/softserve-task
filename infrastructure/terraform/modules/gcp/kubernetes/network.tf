# The nodes get a subnet of their own, with the pod and Service ranges as its
# secondary ranges, and a NAT of their own for the images they pull: the
# workload subnet and its NAT stay exactly as the VMs left them.
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

# GKE opens only 443 and 10250 from the control plane to private nodes. The
# admission webhooks of CloudNativePG (9443) and of the Prometheus operator
# and cert-manager (10250, 10260) listen on pod ports the API server must also
# reach, or every resource they validate is refused with a timeout.
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
