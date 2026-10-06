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

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}
data "aws_availability_zones" "available" { state = "available" }

locals {
  on     = var.enable_egress
  spokes = local.on ? toset(["prod", "dev"]) : toset([])

  vo                = data.terraform_remote_state.vpc.outputs
  shared_public_sub = local.vo.subnet_ids["shared"]
  shared_tgw_rt     = local.vo.shared_tgw_route_table_id
  tgw_id            = data.terraform_remote_state.tgw.outputs.tgw_id
  spoke_tgw_rt      = data.terraform_remote_state.tgw.outputs.spoke_route_table_id
  shared_attach     = data.terraform_remote_state.tgw.outputs.shared_attachment_id
}
