resource "google_service_account" "workload" {
  for_each = local.selected

  account_id   = "${local.prefix}-${each.key}"
  display_name = "${local.prefix}-${each.key}"
  description  = "Runtime identity for the ${local.prefix}-${each.key} workload VM"
}
