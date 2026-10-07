data "aws_partition" "current" {}

locals {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count = local.count

  name               = "${local.prefix}-eks-cluster"
  description        = "Control plane of ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count = local.count

  role       = aws_iam_role.cluster[0].name
  policy_arn = "${local.policy_arn}/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  count = local.count

  name               = "${local.prefix}-eks-nodes"
  description        = "Nodes of ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = local.enabled ? toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ]) : toset([])

  role       = aws_iam_role.nodes[0].name
  policy_arn = "${local.policy_arn}/${each.value}"
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = local.count

  name               = "${local.prefix}-eks-ebs-csi"
  description        = "EBS CSI controller of ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.count

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "${local.policy_arn}/service-role/AmazonEBSCSIDriverPolicy"
}
