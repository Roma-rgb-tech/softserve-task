output "public_ips" {
  description = "External address by VM name, for the VMs that asked for one."
  value       = { for name, address in google_compute_address.public : name => address.address }
}
