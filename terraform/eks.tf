variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = "${var.project}-eks"
  private_subnet_ids  = module.network.private_subnet_ids
  kubernetes_version  = var.kubernetes_version
  public_access_cidrs = [var.admin_cidr]
}

output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
