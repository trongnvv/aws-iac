data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "02-vpn/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}
data "terraform_remote_state" "vpn" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "02-vpn/3-vpn/terraform.tfstate", region = "ap-southeast-1" }
}

# Latest Amazon Linux 2023 (arm64) — same base image as the test hosts. strongSwan and FRR are both
# in the AL2023 default repos for arm64, so the t4g.micro appliance installs them via dnf. (If you
# prefer an x86 base for any package, swap this param to ...-x86_64 and the instance_type to t3.micro.)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  vo = data.terraform_remote_state.vpc.outputs
  no = data.terraform_remote_state.vpn.outputs

  onprem_subnet_id = local.vo.subnet_ids["onprem"]
  onprem_rt_id     = local.vo.route_table_ids["onprem"]
  strongswan_sg_id = local.vo.strongswan_sg_id
  aws_cidr         = local.vo.vpc_cidrs["aws"]    # 10.10/16 — routed to this ENI from the onprem VPC
  onprem_cidr      = local.vo.vpc_cidrs["onprem"] # 192.168/16 — advertised to AWS by FRR
}
