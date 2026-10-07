data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "06-direct-connect/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "tgw" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "06-direct-connect/2-tgw/terraform.tfstate", region = "ap-southeast-1" }
}

locals {
  tgw_id      = data.terraform_remote_state.tgw.outputs.tgw_id
  tgw_rt_id   = data.terraform_remote_state.tgw.outputs.tgw_route_table_id
  aws_rt_id   = data.terraform_remote_state.vpc.outputs.route_table_ids["aws"]
  onprem_cidr = data.terraform_remote_state.vpc.outputs.vpc_cidrs["onprem"]
}
