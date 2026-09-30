locals {
  database_clients = {
    for name, vm in local.selected : name => vm
    if local.managed && contains(["k3s_server", "k3s_agent"], vm.role)
  }
}

resource "google_project_iam_member" "database_client" {
  for_each = local.database_clients

  project = local.project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.workload[each.key].email}"
}
