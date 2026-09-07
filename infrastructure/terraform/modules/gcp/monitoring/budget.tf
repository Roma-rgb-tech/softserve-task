# A budget belongs to the billing account, not to the project, and the filter
# wants the project number rather than its ID. Without a billing_account in the
# configuration no budget is created: the credentials that build the project
# usually cannot see the billing account at all.
data "google_project" "current" {
  count = local.enabled == 1 && local.billing_account != "" && length(local.budget) > 0 ? 1 : 0

  project_id = lookup(lookup(var.config, "gcp", {}), "project_id", "")
}

resource "google_billing_budget" "monthly" {
  count = length(data.google_project.current)

  billing_account = local.billing_account
  display_name    = "${local.prefix} monthly budget"

  budget_filter {
    projects               = ["projects/${data.google_project.current[0].number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = lookup(local.budget, "currency", "USD")
      units         = tostring(floor(local.budget.amount))
    }
  }

  dynamic "threshold_rules" {
    for_each = lookup(local.budget, "thresholds", [0.5, 0.9, 1.0])

    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  # The default recipients are whoever holds billing roles on the account.
  # Turning them off keeps the budget mail going to the same addresses as every
  # other alert, so there is one list to maintain rather than two.
  all_updates_rule {
    monitoring_notification_channels = local.channels
    disable_default_iam_recipients   = true
  }
}
