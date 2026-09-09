locals {
  prepare_disks = file("${path.module}/files/prepare-disks.sh")

  configured = {
    for name, machine in var.machines : name => machine
    if length(machine.disks) > 0
    || length(coalesce(machine.commands, [])) > 0
    || (machine.startup != null && machine.startup != "")
  }
}
