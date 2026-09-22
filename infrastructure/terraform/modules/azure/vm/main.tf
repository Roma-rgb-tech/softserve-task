resource "azurerm_network_interface" "workload" {
  for_each = local.vms

  name                = "${local.prefix}-${each.key}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = each.value.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = each.value.public_subnet ? var.subnets.management : var.subnets.workload
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = lookup(var.public_ip_ids, each.key, null)
  }
}

resource "azurerm_network_interface_application_security_group_association" "workload" {
  for_each = local.group_memberships

  network_interface_id          = azurerm_network_interface.workload[each.value.vm].id
  application_security_group_id = var.security_groups[each.value.role]
}

resource "azurerm_linux_virtual_machine" "workload" {
  for_each = local.vms

  name                = "${local.prefix}-${each.key}"
  computer_name       = "${local.prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = each.value.machine_type
  zone                = local.zone

  disk_controller_type = can(regex("_v[6-9]$", each.value.machine_type)) ? "NVMe" : null

  network_interface_ids = [azurerm_network_interface.workload[each.key].id]

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_public_key
  }

  custom_data = try(base64encode(module.cloudinit.user_data[each.key]), null)

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_ids[each.key]]
  }

  os_disk {
    name                 = "${local.prefix}-${each.key}-root"
    caching              = "ReadWrite"
    storage_account_type = each.value.disk_type
    disk_size_gb         = max(each.value.boot_disk.size_gb, var.minimum_boot_disk_gb)
  }

  source_image_reference {
    publisher = try(local.images[each.key][0], null)
    offer     = try(local.images[each.key][1], null)
    sku       = try(local.images[each.key][2], null)
    version   = try(local.images[each.key][3], null)
  }

  boot_diagnostics {}

  tags = each.value.tags

  lifecycle {
    ignore_changes = [custom_data]

    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }

    precondition {
      condition     = each.value.machine_type != null && each.value.image != null && each.value.disk_type != null
      error_message = "The catalog in the project configuration has no azure mapping for size ${each.value.size}, os ${each.value.os} or disk type ${each.value.boot_disk.type}."
    }

    precondition {
      condition     = try(length(split(":", each.value.image)) == 4, true)
      error_message = "An azure os entry in the catalog must read publisher:offer:sku:version."
    }

    precondition {
      condition     = alltrue([for disk in each.value.extra_disks : disk.disk_type != null])
      error_message = "The catalog has no azure disk_type mapping for one of the extra disks on ${each.key}."
    }
  }
}

resource "azurerm_managed_disk" "extra" {
  for_each = local.extra_disks

  name                 = "${local.prefix}-${each.value.vm}-${each.value.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  zone                 = local.zone
  storage_account_type = each.value.disk_type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb
  tags                 = local.vms[each.value.vm].tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "extra" {
  for_each = local.extra_disks

  managed_disk_id    = azurerm_managed_disk.extra[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.workload[each.value.vm].id
  lun                = each.value.lun
  caching            = "ReadWrite"
}

module "cloudinit" {
  source = "../../shared/cloudinit"

  machines = {
    for name, vm in local.vms : name => {
      hostname = "${local.prefix}-${name}"
      startup  = vm.startup
      commands = vm.commands
      disks = [
        for disk in vm.extra_disks : {
          name       = disk.name
          size_gb    = disk.size_gb
          mount_path = disk.mount_path
        }
      ]
    }
  }
}
