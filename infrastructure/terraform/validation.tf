resource "terraform_data" "config_validation" {
  input = local.cloud

  lifecycle {
    precondition {
      condition     = contains(local.supported_clouds, local.cloud)
      error_message = "config.cloud is \"${local.cloud}\". Supported clouds: ${join(", ", local.supported_clouds)}."
    }

    precondition {
      condition     = local.location != null
      error_message = "config.location is \"${try(local.config.location, "")}\", which has no mapping for cloud \"${local.cloud}\". Known locations: ${join(", ", sort(keys(try(local.catalog.location[local.cloud], {}))))}."
    }

    precondition {
      condition = alltrue([
        for name, vm in local.vms : vm.machine_type != null
      ])
      error_message = "One or more vms[*].size values have no mapping for cloud \"${local.cloud}\". Known sizes: ${join(", ", sort(keys(try(local.catalog.size[local.cloud], {}))))}."
    }

    precondition {
      condition = alltrue([
        for name, vm in local.vms : vm.boot_disk_type != null
      ])
      error_message = "One or more vms[*].boot_disk.type values have no mapping for cloud \"${local.cloud}\". Known disk types: ${join(", ", sort(keys(try(local.catalog.disk_type[local.cloud], {}))))}."
    }

    precondition {
      condition = alltrue([
        for name, vm in local.vms : vm.image != null
      ])
      error_message = "One or more vms[*].os values have no mapping for cloud \"${local.cloud}\". Known operating systems: ${join(", ", sort(keys(try(local.catalog.os[local.cloud], {}))))}."
    }

    precondition {
      condition     = !local.is_gcp || try(local.config.gcp.project_id, "") != ""
      error_message = "cloud is \"gcp\", so the configuration must contain gcp.project_id."
    }
  }
}
