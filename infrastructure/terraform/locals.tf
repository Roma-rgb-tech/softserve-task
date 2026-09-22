locals {
  config = jsondecode(file(var.project_config_path))

  network_overrides = lookup(local.config.network, "clouds", {})

  cloud_config = {
    for cloud in ["gcp", "aws", "azure"] : cloud => merge(local.config, {
      network = merge(local.config.network, lookup(local.network_overrides, cloud, {}))
    })
  }
}
