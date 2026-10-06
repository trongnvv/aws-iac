# One test host per VPC (A, B, C). Ping between their private IPs to prove the routing:
# A↔B and A↔C work; B→C times out (non-transitive).
resource "aws_instance" "test" {
  for_each               = local.subnet_ids
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = each.value
  vpc_security_group_ids = [local.sg_ids[each.key]]
  iam_instance_profile   = data.terraform_remote_state.ssm.outputs.instance_profile_name
  tags                   = { Name = "net-lab-peer-${each.key}" }
}
