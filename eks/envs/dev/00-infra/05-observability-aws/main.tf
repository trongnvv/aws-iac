terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "eks-iac-tfstate"
    key          = "dev/layer0/05-observability-aws/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = "ap-southeast-1"
  profile = "default"
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "eks-iac-tfstate"
    key    = "dev/layer0/01-eks/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

module "observability_aws" {
  source       = "../../../../modules/observability-aws"
  env          = "dev"
  region       = "ap-southeast-1"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  # AWS-native observability, Prometheus flavor (test-plans/03 Part A) — one switch turns on the
  # whole pipeline (AMP + ADOT + Prometheus + Fluent Bit + Grafana IAM). The AMP workspace survives
  # teardown.sh (only the IAM roles are destroyed) so its ID — hardcoded in the 02-platform values —
  # stays stable across redeploys.
  enable_amp = true

  # Alerting (test-plans/03 §A7): AMP rules + Alert Manager → SNS. SNS-only for now (no Slack);
  # add alert_teams{ <team> = { slack_channel_id } } + alert_slack_workspace_id to wire Chatbot.
  enable_alerting = true

  # Alert rules authored as plain YAML in rules/*.yaml (one AMP rule-group namespace per file).
  alert_rule_groups = {
    for f in fileset("${path.module}/rules", "*.yaml") : trimsuffix(f, ".yaml") => file("${path.module}/rules/${f}")
  }
}

output "amp_workspace_arn" { value = module.observability_aws.amp_workspace_arn }
output "amp_remote_write_url" { value = module.observability_aws.amp_remote_write_url }
output "amp_endpoint" { value = module.observability_aws.amp_endpoint }
output "alert_sns_topic_arns" { value = module.observability_aws.alert_sns_topic_arns }
