variable "project" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }

variable "admin_cidr" {
  description = "CIDR allowed to reach SSH and Jenkins through the public NACL"
  type        = string
  default     = "0.0.0.0/0"
}
