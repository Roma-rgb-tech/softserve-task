data "aws_ami" "boot" {
  for_each = local.vms

  most_recent = true
  owners      = [var.image_owner]

  filter {
    name   = "name"
    values = [each.value.image]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "workload" {
  for_each = local.vms

  ami           = data.aws_ami.boot[each.key].id
  instance_type = each.value.machine_type

  subnet_id              = each.value.public_subnet ? var.subnets.management : var.subnets.workload
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [for role in each.value.network_tags : var.security_groups[role]]
  iam_instance_profile   = var.instance_profiles[each.key]
  key_name               = var.key_name

  associate_public_ip_address = false

  user_data = each.value.startup

  root_block_device {
    volume_size = each.value.boot_disk.size_gb
    volume_type = each.value.disk_type
    iops        = contains(local.needs_iops, each.value.disk_type) ? each.value.iops : null
    encrypted   = true

    tags = merge(each.value.tags, { Name = "${local.prefix}-${each.key}-root" })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  lifecycle {
    ignore_changes = [associate_public_ip_address]

    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }

    precondition {
      condition     = length(local.regions) > 0
      error_message = "A VM targets aws, so the configuration must contain aws.regions for the dynamic inventory to search."
    }

    precondition {
      condition     = each.value.machine_type != null && each.value.image != null && each.value.disk_type != null
      error_message = "The catalog in the project configuration has no aws mapping for size ${each.value.size}, os ${each.value.os} or disk type ${each.value.boot_disk.type}."
    }

    precondition {
      condition     = !contains(local.needs_iops, each.value.disk_type) || each.value.iops != null
      error_message = "Disk type ${each.value.boot_disk.type} resolves to ${each.value.disk_type} on aws, which requires boot_disk.iops in the project configuration."
    }
  }

  tags = merge(each.value.tags, { Name = "${local.prefix}-${each.key}" })
}
