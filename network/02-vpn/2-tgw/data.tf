data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "network-iac-tfstate"
    key    = "02-vpn/1-vpc/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

locals {
  vo            = data.terraform_remote_state.vpc.outputs
  aws_vpc_id    = local.vo.vpc_ids["aws"]
  aws_subnet_id = local.vo.subnet_ids["aws"]
  aws_rt_id     = local.vo.route_table_ids["aws"]
  onprem_cidr   = local.vo.vpc_cidrs["onprem"] # 192.168.0.0/16 — what the aws VPC routes to the TGW
}
