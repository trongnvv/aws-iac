data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "05-peering/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "ssm" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "05-peering/3-ssm/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed test host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
  sg_ids     = data.terraform_remote_state.vpc.outputs.sg_ids
}
