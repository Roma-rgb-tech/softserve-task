output "public_ip_ids" {
  description = "Public IP resource identifier by VM name. Azure attaches the address to a network interface, so the VMs are created after it."
  value       = { for name, address in azurerm_public_ip.public : name => address.id }
}

output "public_ips" {
  description = "External address by VM name, for the VMs that asked for one."
  value       = { for name, address in azurerm_public_ip.public : name => address.ip_address }
}
