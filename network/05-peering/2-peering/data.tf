data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "network-iac-tfstate"
    key    = "05-peering/1-vpc/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  vpc_ids = data.terraform_remote_state.vpc.outputs.vpc_ids
  rt_ids  = data.terraform_remote_state.vpc.outputs.route_table_ids
  cidrs   = data.terraform_remote_state.vpc.outputs.vpc_cidrs
}
