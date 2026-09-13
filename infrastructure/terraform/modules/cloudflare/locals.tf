locals {
  endpoints = {
    for name, vm in var.config.vms : name => vm.public_endpoint
    if lookup(vm, "public_endpoint", null) != null
    && lookup(vm.public_endpoint, "cloudflare_zone_id", "") != ""
  }
}
