terraform {
  required_version = ">= 1.9.0"

  # Partial backend — bucket/key/region/table supplied at init via
  # `-backend-config` (scripts/deploy.sh + envs/<env>/backend.hcl). The key is
  # prefixed per env so multiple systems don't share state.
  backend "s3" {}

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}
