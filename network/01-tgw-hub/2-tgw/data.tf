data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "network-iac-tfstate"
    key    = "01-tgw-hub/1-vpc/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  vpc_ids    = data.terraform_remote_state.vpc.outputs.vpc_ids
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
  rt_ids     = data.terraform_remote_state.vpc.outputs.route_table_ids
  # shared's attachment goes in its dedicated tgw subnet (egress-ready); spokes use their public subnet.
  attach_subnet = merge(local.subnet_ids, { shared = data.terraform_remote_state.vpc.outputs.shared_tgw_subnet_id })
}
