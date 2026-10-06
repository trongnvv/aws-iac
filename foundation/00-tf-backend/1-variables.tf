variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

# Globally-unique state buckets (one per domain). Add a name here → it gets the same
# versioning/encryption/public-access-block. eks + foundation use eks-iac-tfstate; network/* labs
# use network-iac-tfstate.
variable "state_buckets" {
  type    = set(string)
  default = ["eks-iac-tfstate", "network-iac-tfstate"]
}
