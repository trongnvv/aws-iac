data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "04-route53-resolver/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "onprem" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "04-route53-resolver/3-onprem-dns/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — ships `dig` after a quick `dnf install bind-utils`.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  # One test host per side. aws host → dig host1.corp.local (via outbound); onprem host → dig
  # test.aws.internal (via inbound/PHZ). Each lands in its own VPC's subnet + SG.
  hosts = {
    aws    = { subnet_id = data.terraform_remote_state.vpc.outputs.aws_subnet_ids["a"], sg_id = data.terraform_remote_state.vpc.outputs.sg_ids["aws"] }
    onprem = { subnet_id = data.terraform_remote_state.vpc.outputs.onprem_subnet_id, sg_id = data.terraform_remote_state.vpc.outputs.sg_ids["onprem"] }
  }

  instance_profile = data.terraform_remote_state.onprem.outputs.instance_profile_name

  # Per-host user_data. Both install dig; the on-prem host additionally points its resolver at the
  # dnsmasq box so aws.internal lookups go on-prem → inbound endpoint → PHZ.
  user_data = {
    aws    = <<-EOF
      #!/bin/bash
      set -eux
      dnf install -y bind-utils
    EOF
    onprem = <<-EOF
      #!/bin/bash
      set -eux
      dnf install -y bind-utils
      # Use the simulated on-prem DNS server as this host's resolver.
      echo "nameserver ${data.terraform_remote_state.onprem.outputs.onprem_dns_ip}" >/etc/resolv.conf
    EOF
  }
}
