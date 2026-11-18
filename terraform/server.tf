variable "admin_cidr" {
  description = "Your public IP as x.x.x.x/32. Used by the NACL and the Jenkins security group"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ami_id" {
  type    = string
  default = null
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/ivolve-jenkins.pub"
}

module "server" {
  source = "./modules/server"

  project         = var.project
  vpc_id          = module.network.vpc_id
  subnet_id       = module.network.public_subnet_ids[0]
  ami_id          = var.ami_id
  public_key_path = pathexpand(var.public_key_path)
  admin_cidr      = var.admin_cidr
}

output "jenkins_public_ip" { value = module.server.public_ip }
output "jenkins_instance_id" { value = module.server.instance_id }
