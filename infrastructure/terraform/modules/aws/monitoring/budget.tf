resource "aws_budgets_budget" "monthly" {
  count = local.enabled == 1 && length(local.budget) > 0 ? 1 : 0

  name         = "${local.prefix}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(local.budget.amount)
  limit_unit   = lookup(local.budget, "currency", "USD")

  dynamic "notification" {
    for_each = lookup(local.budget, "thresholds", [0.5, 0.9, 1.0])

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value * 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = local.emails
    }
  }
}
