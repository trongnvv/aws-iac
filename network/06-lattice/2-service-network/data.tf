data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "06-lattice/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

locals {
  vpc_ids = data.terraform_remote_state.vpc.outputs.vpc_ids
  sg_ids  = data.terraform_remote_state.vpc.outputs.sg_ids
}
