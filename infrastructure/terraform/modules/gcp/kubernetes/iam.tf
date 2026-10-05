# The nodes run as an account of their own with only what GKE needs to report
# logs and metrics - not as the Compute Engine default account, which holds
# Editor on the project.
resource "google_service_account" "nodes" {
  count = local.count

  account_id   = "${local.prefix}-gke-nodes"
  display_name = "${local.prefix}-gke-nodes"
  description  = "Runtime identity of the ${local.name} nodes"
}

locals {
  node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = local.enabled ? toset(local.node_roles) : toset([])

  project = local.project
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}
