variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# Wired from the eks module output by the env root.
variable "cluster_name" {
  type = string
}
