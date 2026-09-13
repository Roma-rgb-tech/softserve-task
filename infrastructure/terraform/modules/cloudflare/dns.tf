resource "cloudflare_dns_record" "endpoint" {
  for_each = local.endpoints

  zone_id = each.value.cloudflare_zone_id
  name    = each.value.hostname
  type    = "A"
  content = var.vms[each.key].public_ip
  ttl     = 300
  proxied = false
  comment = "Managed by Terraform for the ${each.key} workload"

  lifecycle {
    precondition {
      condition     = var.vms[each.key].public_ip != null
      error_message = "Workload ${each.key} has a public_endpoint but no public IP - set assign_public_ip to true for it."
    }
  }
}
