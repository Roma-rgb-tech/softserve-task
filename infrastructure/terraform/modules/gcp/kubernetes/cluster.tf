resource "google_project_service" "container" {
  count = local.count

  project            = local.project
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_container_cluster" "main" {
  count = local.count

  name     = local.name
  location = local.zone

  network    = var.network_id
  subnetwork = google_compute_subnetwork.nodes[0].id

  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.nodes[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  min_master_version  = local.version
  deletion_protection = false

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = local.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.api_cidrs

      content {
        cidr_block   = cidr_blocks.value
        display_name = "operator ${cidr_blocks.key}"
      }
    }
  }

  release_channel {
    channel = local.version == null ? "REGULAR" : "UNSPECIFIED"
  }

  workload_identity_config {
    workload_pool = "${local.project}.svc.id.goog"
  }

  resource_labels = local.labels

  depends_on = [google_compute_router_nat.nodes, google_project_service.container, google_project_iam_member.nodes]

  lifecycle {
    ignore_changes = [node_config]
    precondition {
      condition     = local.zone != null && local.region != null
      error_message = "catalog.zone.gcp and catalog.region.gcp need an entry for default_region ${local.token}."
    }

    precondition {
      condition     = length(local.api_cidrs) > 0
      error_message = "Nothing would be allowed to reach the GKE API. Set kubernetes.api_allowed_cidrs, or allowed_cidrs on the bastion."
    }
  }
}

resource "google_container_node_pool" "main" {
  count = local.count

  name     = "default"
  cluster  = google_container_cluster.main[0].id
  location = local.zone

  node_count = local.node_count
  version    = local.version == null ? null : google_container_cluster.main[0].master_version

  node_config {
    machine_type    = local.machine_type
    disk_type       = local.disk_type
    disk_size_gb    = local.disk_gb
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    tags            = [local.node_tag]
    labels          = { role = "kubernetes-node" }
    resource_labels = local.labels

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = local.version == null
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  depends_on = [google_project_iam_member.nodes]

  lifecycle {
    precondition {
      condition     = local.machine_type != null
      error_message = "catalog.size.gcp has no entry for kubernetes.node_size."
    }
  }
}
