output "secret_resource_names" {
  description = "Versionless secret identifiers, by secret ID. Never values."
  value       = { for secret_id, secret in azurerm_key_vault_secret.this : secret_id => secret.versionless_id }
}

output "key_vault_name" {
  description = "Key Vault that holds every secret of this stand, or null when no Azure VM reads one."
  value       = one(azurerm_key_vault.main[*].name)
}
