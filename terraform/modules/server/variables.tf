variable "project" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }

variable "ami_id" {
  description = "AMI to use. When null, the latest Ubuntu 22.04 AMI is looked up"
  type        = string
  default     = null
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "public_key_path" {
  description = "Path of the SSH public key to import"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to reach SSH and Jenkins"
  type        = string
}

variable "root_volume_size" {
  type    = number
  default = 30
}
