# One test host per VPC: aws-side (10.30.0.x) and onprem-side (192.168.0.x). SSM into each and ping
# across the link. Both use the shared SG (ICMP from both sides) + the SSM instance profile from
# 5-strongswan. No SSH key.
resource "aws_instance" "test" {
  for_each               = local.subnet_ids
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = each.value
  vpc_security_group_ids = [local.sg_ids[each.key]]
  iam_instance_profile   = data.terraform_remote_state.strongswan.outputs.instance_profile_name
  tags                   = { Name = "net-lab-dx-${each.key}-test" }
}
