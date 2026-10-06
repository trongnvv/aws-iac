terraform {
  required_version = ">= 1.9.0"
  backend "s3" {
    bucket       = "network-iac-tfstate"
    key          = "01-tgw-hub/3-ssm/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Instance role for Session Manager — lets us `aws ssm start-session` into the test hosts with no SSH
# key and no bastion. Shared by all test EC2s (layer 4-ec2).
resource "aws_iam_role" "ssm" {
  name = "net-lab-ssm"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "net-lab-ssm"
  role = aws_iam_role.ssm.name
}

output "instance_profile_name" { value = aws_iam_instance_profile.ssm.name }
