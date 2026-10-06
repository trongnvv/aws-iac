data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "02-vpn/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

# The SSM instance profile is created in 4-strongswan (the first instance layer) and reused here.
data "terraform_remote_state" "strongswan" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "02-vpn/4-strongswan/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed test host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
  sg_ids     = data.terraform_remote_state.vpc.outputs.sg_ids
}
