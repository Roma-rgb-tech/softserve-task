resource "aws_eks_cluster" "main" {
  count = local.count

  name     = local.name
  version  = local.version
  role_arn = aws_iam_role.cluster[0].arn

  vpc_config {
    subnet_ids              = [for key in ["primary", "secondary"] : aws_subnet.nodes[key].id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = local.api_cidrs
  }

  kubernetes_network_config {
    service_ipv4_cidr = local.service_cidr
  }

  # Access entries rather than the aws-auth ConfigMap. Whoever runs Terraform
  # becomes cluster administrator, the same identity Ansible runs as.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.cluster]

  lifecycle {
    precondition {
      condition     = local.zone != null
      error_message = "catalog.zone.aws needs an entry for default_region ${local.token}."
    }

    precondition {
      condition     = length(local.api_cidrs) > 0
      error_message = "Nothing would be allowed to reach the EKS API. Set kubernetes.api_allowed_cidrs, or allowed_cidrs on the bastion."
    }
  }
}

resource "aws_eks_node_group" "main" {
  count = local.count

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.nodes[0].arn
  subnet_ids      = [aws_subnet.nodes["primary"].id]

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = [local.instance_type]
  disk_size      = local.disk_gb

  scaling_config {
    desired_size = local.node_count
    min_size     = local.node_count
    max_size     = local.node_count
  }

  update_config {
    max_unavailable = 1
  }

  labels = { role = "kubernetes-node" }
  tags   = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.nodes,
    aws_route_table_association.nodes,
  ]

  lifecycle {
    precondition {
      condition     = local.instance_type != null
      error_message = "catalog.size.aws has no entry for kubernetes.node_size."
    }
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  count = local.count

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  count = local.count

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi[0].arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
