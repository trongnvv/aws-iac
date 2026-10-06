data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/1-vpc/terraform.tfstate", region = "ap-southeast-1" }
}

data "terraform_remote_state" "provider" {
  backend = "s3"
  config  = { bucket = "network-iac-tfstate", key = "03-privatelink/2-provider/terraform.tfstate", region = "ap-southeast-1" }
}

locals {
  vpc_b_id            = data.terraform_remote_state.vpc.outputs.vpc_ids["b"]
  subnet_b            = data.terraform_remote_state.vpc.outputs.subnet_ids["b"]
  vpc_b_cidr          = data.terraform_remote_state.vpc.outputs.vpc_cidrs["b"]
  endpoint_service_nm = data.terraform_remote_state.provider.outputs.endpoint_service_name
}
