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

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.vms

  name               = "${local.resource_prefix}-${each.key}"
  description        = "Runtime identity for the ${local.resource_prefix}-${each.key} workload VM"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = each.value.tags
}

resource "aws_iam_instance_profile" "workload" {
  for_each = local.vms

  name = "${local.resource_prefix}-${each.key}"
  role = aws_iam_role.workload[each.key].name

  tags = each.value.tags
}

resource "aws_instance" "workload" {
  for_each = local.vms

  ami           = data.aws_ami.boot[each.key].id
  instance_type = each.value.machine_type

  subnet_id              = each.value.public_subnet ? aws_subnet.management[0].id : aws_subnet.workload[0].id
  private_ip             = each.value.internal_ip
  vpc_security_group_ids = [for tag in each.value.network_tags : local.security_groups[tag]]
  iam_instance_profile   = aws_iam_instance_profile.workload[each.key].name

  associate_public_ip_address = false

  root_block_device {
    volume_size = each.value.boot_disk.size_gb
    volume_type = each.value.disk_type
    iops        = contains(local.iops_required, each.value.disk_type) ? var.boot_disk_iops : null
    encrypted   = true

    tags = merge(each.value.tags, { Name = "${local.resource_prefix}-${each.key}-root" })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/templates/ssh-users.yaml.tftpl", {
    ssh_users = local.config.ssh_users
  })

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }

    precondition {
      condition     = length(lookup(lookup(local.config, "aws", {}), "regions", [])) > 0
      error_message = "A VM targets aws, so the configuration must contain aws.regions for the dynamic inventory to search."
    }

    precondition {
      condition     = each.value.machine_type != null && each.value.image != null && each.value.disk_type != null
      error_message = "The catalog in the project configuration has no aws mapping for size ${each.value.size}, os ${each.value.os} or disk type ${each.value.boot_disk.type}."
    }
  }

  tags = merge(each.value.tags, { Name = "${local.resource_prefix}-${each.key}" })
}

resource "aws_eip" "public" {
  for_each = local.public_vms

  domain   = "vpc"
  instance = aws_instance.workload[each.key].id

  tags = merge(each.value.tags, { Name = "${local.resource_prefix}-${each.key}-ip" })
}
