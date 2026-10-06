data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "04-route53-resolver/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

locals {
  aws_vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_ids["aws"]
  aws_subnet_ids = data.terraform_remote_state.vpc.outputs.aws_subnet_ids # { a=.., b=.. }
  onprem_cidr    = data.terraform_remote_state.vpc.outputs.onprem_cidr
}
