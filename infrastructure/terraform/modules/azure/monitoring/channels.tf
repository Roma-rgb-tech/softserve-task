resource "azurerm_monitor_action_group" "email" {
  count = local.enabled

  name                = "${local.prefix}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace(local.prefix, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = local.emails

    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}
