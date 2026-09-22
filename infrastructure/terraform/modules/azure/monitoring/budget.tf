resource "azurerm_consumption_budget_resource_group" "monthly" {
  count = local.enabled == 1 && length(local.budget) > 0 ? 1 : 0

  name              = "${local.prefix}-monthly"
  resource_group_id = var.resource_group_id
  amount            = local.budget.amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  dynamic "notification" {
    for_each = lookup(local.budget, "thresholds", [0.5, 0.9, 1.0])

    content {
      enabled        = true
      threshold      = notification.value * 100
      threshold_type = "Actual"
      operator       = "GreaterThan"
      contact_emails = local.emails
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
