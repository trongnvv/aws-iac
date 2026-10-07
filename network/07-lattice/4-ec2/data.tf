data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "07-lattice/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "service" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "07-lattice/3-service/terraform.tfstate", region = "ap-southeast-1" }
}

# Same AL2023 arm64 AMI as every other host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  # Client lives in VPC A.
  subnet_a_id = data.terraform_remote_state.vpc.outputs.subnet_ids["a"]
  sg_a_id     = data.terraform_remote_state.vpc.outputs.sg_ids["a"]

  instance_profile = data.terraform_remote_state.service.outputs.instance_profile_name
  service_dns_name = data.terraform_remote_state.service.outputs.service_dns_name
}
