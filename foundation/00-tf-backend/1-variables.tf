variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Globally-unique bucket name.
variable "state_bucket_name" {
  default = "eks-iac-tfstate"
}
