data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "provider" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/2-provider/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "consumer" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/3-consumer/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed test host.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  subnet_b          = data.terraform_remote_state.vpc.outputs.subnet_ids["b"]
  consumer_sg_id    = data.terraform_remote_state.vpc.outputs.consumer_host_sg_id
  instance_profile  = data.terraform_remote_state.provider.outputs.instance_profile_name
  endpoint_dns_name = data.terraform_remote_state.consumer.outputs.endpoint_dns_name
}
