data "aws_region" "current" {}

output "cluster" {
  description = "The managed cluster, for Ansible to fetch credentials for. Null when EKS is not in use."
  value = local.enabled ? {
    cloud    = local.cloud
    kind     = "eks"
    name     = aws_eks_cluster.main[0].name
    location = data.aws_region.current.region
    project  = null
    endpoint = aws_eks_cluster.main[0].endpoint
    version  = aws_eks_cluster.main[0].version
    context  = local.name
  } : null
}
