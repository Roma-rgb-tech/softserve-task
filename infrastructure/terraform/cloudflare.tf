resource "cloudflare_dns_record" "endpoint" {
  for_each = {
    for name, vm in local.config.vms : name => vm.public_endpoint
    if lookup(vm, "public_endpoint", null) != null
    && lookup(vm.public_endpoint, "cloudflare_zone_id", "") != ""
  }

  zone_id = each.value.cloudflare_zone_id
  name    = each.value.hostname
  type    = "A"
  content = local.vms[each.key].public_ip
  ttl     = 1
  proxied = false
  comment = "Managed by Terraform for the ${each.key} workload"

  lifecycle {
    precondition {
      condition     = local.vms[each.key].public_ip != null
      error_message = "Workload ${each.key} has a public_endpoint but no public IP - set assign_public_ip to true for it."
    }
  }
}
