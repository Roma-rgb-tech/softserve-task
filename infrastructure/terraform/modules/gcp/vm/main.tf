resource "google_compute_instance" "workload" {
  for_each = local.vms

  name                      = "${local.prefix}-${each.key}"
  machine_type              = each.value.machine_type
  zone                      = local.zone
  allow_stopping_for_update = true

  tags   = each.value.tags
  labels = each.value.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = each.value.image
      size   = each.value.boot_disk.size_gb
      type   = each.value.disk_type
      labels = each.value.labels
    }
  }

  dynamic "attached_disk" {
    for_each = each.value.extra_disks

    content {
      source      = google_compute_disk.extra["${each.key}/${attached_disk.value.name}"].id
      device_name = attached_disk.value.name
      mode        = "READ_WRITE"
    }
  }

  network_interface {
    subnetwork = each.value.public_subnet ? var.subnets.management : var.subnets.workload
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = var.public_ips[each.key]
      }
    }
  }

  service_account {
    email  = var.runtime_identities[each.key]
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }

    precondition {
      condition     = local.project_id != ""
      error_message = "A VM targets gcp, so the configuration must contain gcp.project_id."
    }

    precondition {
      condition     = each.value.machine_type != null && each.value.image != null && each.value.disk_type != null
      error_message = "The catalog in the project configuration has no gcp mapping for size ${each.value.size}, os ${each.value.os} or disk type ${each.value.boot_disk.type}."
    }
  }

  metadata = merge(
    {
      "enable-oslogin" = "FALSE"
      "ssh-keys"       = local.ssh_keys
    },
    lookup(module.cloudinit.user_data, each.key, null) == null ? {} : {
      "user-data" = module.cloudinit.user_data[each.key]
    },
  )
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
