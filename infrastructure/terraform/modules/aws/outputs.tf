output "vms" {
  description = "One entry per VM this cloud created, in the shape the root module merges across clouds."
  value = {
    for name, vm in module.vm.vms :
    name => merge(vm, { public_ip = lookup(module.addresses.public_ips, name, null) })
  }
}

output "region" {
  description = "Provider region this cloud deployed into, or null when it created nothing."
  value       = module.vm.region
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by secret ID. Never values."
  value       = module.secrets.secret_resource_names
}

output "monitoring" {
  description = "What CloudWatch set up: the dashboard, and how an alert leaves the cloud."
  value = {
    dashboard = module.monitoring.dashboard_name
    delivery  = module.monitoring.alert_topic_arn
  }
}
