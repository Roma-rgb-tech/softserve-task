locals {
  telemetry_roles = ["roles/monitoring.metricWriter", "roles/logging.logWriter"]

  telemetry = {
    for pair in setproduct(sort(keys(local.selected)), local.telemetry_roles) :
    "${pair[0]}/${pair[1]}" => { vm = pair[0], role = pair[1] }
  }
}

# Writing a metric or a log line is a project-level permission - Cloud
# Monitoring and Cloud Logging have no per-resource form of it. Both roles are
# write-only: neither can read back a metric, a log entry, or anything else in
# the project, so this does not widen what a compromised VM can see.
resource "google_project_iam_member" "telemetry" {
  for_each = local.monitored ? local.telemetry : {}

  project = local.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.vm].email}"
}
