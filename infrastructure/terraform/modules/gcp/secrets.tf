resource "google_secret_manager_secret" "this" {
  for_each = toset(local.secret_ids)

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = { for pair in local.workload_secret_pairs : "${pair.vm_name}/${pair.secret_id}" => pair }

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload[each.value.vm_name].email}"
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
