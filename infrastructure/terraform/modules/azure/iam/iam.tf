resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.selected

  name                = "${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.tags, { role = each.value.role })
}
