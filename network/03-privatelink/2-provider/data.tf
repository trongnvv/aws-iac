data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed service host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  vpc_a_id  = data.terraform_remote_state.vpc.outputs.vpc_ids["a"]
  subnet_a  = data.terraform_remote_state.vpc.outputs.subnet_ids["a"]
  svc_sg_id = data.terraform_remote_state.vpc.outputs.provider_svc_sg_id
}
