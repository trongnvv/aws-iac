data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "07-lattice/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "sn" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "07-lattice/2-service-network/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed host. Same AMI as every other lab.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  # Service lives in VPC B.
  vpc_b_id    = data.terraform_remote_state.vpc.outputs.vpc_ids["b"]
  subnet_b_id = data.terraform_remote_state.vpc.outputs.subnet_ids["b"]
  sg_b_id     = data.terraform_remote_state.vpc.outputs.sg_ids["b"]

  service_network_id = data.terraform_remote_state.sn.outputs.service_network_id
}
