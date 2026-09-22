data "azurerm_client_config" "current" {}

resource "random_id" "vault" {
  count = local.enabled

  byte_length = 3
}

resource "azurerm_key_vault" "main" {
  count = local.enabled

  name                = "${local.vault_prefix}-kv-${random_id.vault[0].hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = local.retention

  tags = local.tags
}

resource "azurerm_role_assignment" "deployer" {
  count = local.enabled

  scope                = azurerm_key_vault.main[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "deployer_propagation" {
  count = local.enabled

  create_duration = "90s"

  triggers = {
    role_assignment = azurerm_role_assignment.deployer[0].id
  }
}

ephemeral "random_password" "placeholder" {
  for_each = toset(local.secret_ids)

  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "this" {
  for_each = toset(local.secret_ids)

  name             = each.value
  key_vault_id     = azurerm_key_vault.main[0].id
  value_wo         = ephemeral.random_password.placeholder[each.value].result
  value_wo_version = 1
  content_type     = "unset"
  tags             = local.tags

  depends_on = [time_sleep.deployer_propagation]

  lifecycle {
    ignore_changes = [content_type, tags, expiration_date, not_before_date]
  }
}

resource "azurerm_role_assignment" "workload_access" {
  for_each = local.access_pairs

  scope                = azurerm_key_vault_secret.this[each.value.secret_id].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.principal_ids[each.value.vm_name]
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "version_adder" {
  for_each = local.version_writers

  scope                = azurerm_key_vault_secret.this[each.value.secret_id].resource_versionless_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value.principal

  lifecycle {
    precondition {
      condition = alltrue([
        for principal in local.managers :
        can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", principal))
      ])
      error_message = "Each azure.secret_version_managers entry must be an Entra ID object ID."
    }
  }
}
