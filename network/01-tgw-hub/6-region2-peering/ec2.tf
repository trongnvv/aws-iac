# Test host in region2 — SSM only, same instance profile as every other net-lab host (IAM is
# global, no need to recreate the role per region).
resource "aws_instance" "region2_test" {
  count                  = local.on ? 1 : 0
  provider               = aws.region2
  ami                    = data.aws_ssm_parameter.al2023_region2.value
  instance_type          = "t4g.micro"
  subnet_id              = aws_subnet.region2[0].id
  vpc_security_group_ids = [aws_security_group.region2[0].id]
  iam_instance_profile   = data.terraform_remote_state.ssm.outputs.instance_profile_name
  tags                   = { Name = "net-lab-region2-test" }
}
