output "public_ips" {
  description = "External address by VM name, for the VMs that asked for one."
  value       = { for name, address in aws_eip.public : name => address.public_ip }
}
