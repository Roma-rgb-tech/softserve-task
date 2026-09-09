output "user_data" {
  description = "Rendered cloud-config by machine name. Machines that need no first-boot work are absent, so the caller passes null for them."
  value = {
    for name, machine in local.configured : name => templatefile(
      "${path.module}/templates/cloud-init.yaml.tftpl",
      {
        hostname      = machine.hostname
        disks         = machine.disks
        commands      = coalesce(machine.commands, [])
        startup       = machine.startup == null ? "" : machine.startup
        prepare_disks = local.prepare_disks
      }
    )
  }
}
