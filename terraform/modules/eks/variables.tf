variable "cluster_name" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint"
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}
