data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}
data "terraform_remote_state" "tgw" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/2-tgw/terraform.tfstate", region = "ap-southeast-1" }
}
data "terraform_remote_state" "ssm" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "01-tgw-hub/3-ssm/terraform.tfstate", region = "ap-southeast-1" }
}

data "aws_ssm_parameter" "al2023_region2" {
  provider = aws.region2
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}
data "aws_availability_zones" "region2" {
  provider = aws.region2
  state    = "available"
}

locals {
  on = var.enable_peering

  home_tgw_id       = data.terraform_remote_state.tgw.outputs.tgw_id
  home_shared_rt_id = data.terraform_remote_state.tgw.outputs.shared_route_table_id
  home_shared_cidr  = data.terraform_remote_state.vpc.outputs.vpc_cidrs["shared"] # what region2 learns to reach
}
