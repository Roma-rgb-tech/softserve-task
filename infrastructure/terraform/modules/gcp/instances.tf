resource "google_service_account" "workload" {
  for_each = local.vms

  account_id   = "${local.resource_prefix}-${each.key}"
  display_name = "${local.resource_prefix}-${each.key}"
  description  = "Runtime identity for the ${local.resource_prefix}-${each.key} workload VM"

  depends_on = [google_project_service.required]
}

resource "google_compute_address" "public" {
  for_each = local.public_vms

  name   = "${local.resource_prefix}-${each.key}-ip"
  region = local.region
  labels = each.value.labels
}

#trivy:ignore:AVD-GCP-0031[assign_public_ip=true]
resource "google_compute_instance" "workload" {
  for_each = local.vms

  name                      = "${local.resource_prefix}-${each.key}"
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

  network_interface {
    subnetwork = each.value.public_subnet ? google_compute_subnetwork.management[0].id : google_compute_subnetwork.workload[0].id
    network_ip = each.value.internal_ip

    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []

      content {
        nat_ip = google_compute_address.public[each.key].address
      }
    }
  }

  service_account {
    email  = google_service_account.workload[each.key].email
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
      condition     = lookup(lookup(local.config, "gcp", {}), "project_id", "") != ""
      error_message = "A VM targets gcp, so the configuration must contain gcp.project_id."
    }

    precondition {
      condition     = each.value.machine_type != null && each.value.image != null && each.value.disk_type != null
      error_message = "The catalog in the project configuration has no gcp mapping for size ${each.value.size}, os ${each.value.os} or disk type ${each.value.boot_disk.type}."
    }
  }

  metadata = {
    "enable-oslogin" = "FALSE"
    "ssh-keys" = join("\n", [
      for username, public_key in local.config.ssh_users :
      "${username}:${trimspace(public_key)}"
    ])
  }
}
