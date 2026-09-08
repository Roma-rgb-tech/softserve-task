locals {
  labels = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud
  }, var.config.common_labels)
}

resource "google_secret_manager_secret" "this" {
  for_each = toset(local.secret_ids)

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "workload_access" {
  for_each = local.access_pairs

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.runtime_identities[each.value.vm_name]}"
}

resource "google_secret_manager_secret_iam_member" "version_viewer" {
  for_each = local.version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.viewer"
  member    = each.value.member
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member

  lifecycle {
    precondition {
      condition = alltrue([
        for member in local.managers :
        can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
      ])
      error_message = "Each gcp.secret_version_managers entry must be a fully qualified IAM member, for example user:name@example.com."
    }
  }
}
