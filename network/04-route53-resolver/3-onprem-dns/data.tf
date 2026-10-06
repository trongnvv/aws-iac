data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "04-route53-resolver/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "dns" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "04-route53-resolver/2-dns/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — small, SSM-managed host running dnsmasq.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  onprem_subnet_id = data.terraform_remote_state.vpc.outputs.onprem_subnet_id
  onprem_sg_id     = data.terraform_remote_state.vpc.outputs.sg_ids["onprem"]

  # Inbound Resolver endpoint IPs — dnsmasq forwards *.aws.internal to these (templated into user_data).
  inbound_ips = data.terraform_remote_state.dns.outputs.inbound_ips
}
