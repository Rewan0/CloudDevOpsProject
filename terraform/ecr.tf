variable "ecr_repositories" {
  type    = list(string)
  default = ["frontend", "auth-service", "roadmap-service"]
}

module "ecr" {
  source = "./modules/ecr"

  project      = var.project
  repositories = var.ecr_repositories
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
