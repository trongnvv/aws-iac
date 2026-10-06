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

# Buckets that ALREADY exist in AWS → adopt into state via config-driven import (no recreate).
# Must be a subset of state_buckets that truly exists. Fresh account (nothing created yet): set to [].
variable "adopt_buckets" {
  type    = set(string)
  default = ["eks-iac-tfstate"]
}
