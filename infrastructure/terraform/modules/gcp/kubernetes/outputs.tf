output "cluster" {
  description = "The managed cluster, for Ansible to fetch credentials for. Null when GKE is not in use."
  value = local.enabled ? {
    cloud    = local.cloud
    kind     = "gke"
    name     = google_container_cluster.main[0].name
    location = local.zone
    group    = null
    project  = local.project
    endpoint = google_container_cluster.main[0].endpoint
    version  = google_container_cluster.main[0].master_version
    context  = "gke_${local.project}_${local.zone}_${google_container_cluster.main[0].name}"
  } : null
}
