locals {
  telemetry_roles = ["roles/monitoring.metricWriter", "roles/logging.logWriter"]

  telemetry = {
    for pair in setproduct(sort(keys(local.selected)), local.telemetry_roles) :
    "${pair[0]}/${pair[1]}" => { vm = pair[0], role = pair[1] }
  }
}

resource "google_project_iam_member" "telemetry" {
  for_each = local.monitored ? local.telemetry : {}

  project = local.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.vm].email}"
}
