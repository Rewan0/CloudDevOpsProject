variable "project" { type = string }

variable "repositories" {
  description = "One ECR repository is created per name"
  type        = list(string)
}

variable "image_tag_mutability" {
  type    = string
  default = "MUTABLE"
}

variable "max_image_count" {
  type    = number
  default = 10
}

variable "force_delete" {
  description = "Allow terraform destroy to remove repositories that still contain images"
  type        = bool
  default     = true
}
