variable "use_floci" {
  type    = bool
  default = true
}
variable "floci_endpoint" {
  type    = string
  default = "http://localhost:4566"
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}
variable "project" {
  type    = string
  default = "ivolve"
}
