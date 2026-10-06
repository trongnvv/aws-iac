# Two SSM test hosts — one per VPC. They inherit the VPC's default resolver (.2):
#   * aws host  → *.corp.local  resolves via the outbound endpoint + corp.local forwarding rule.
#   * onprem host → *.aws.internal resolves because its /etc/resolv.conf points at the dnsmasq box,
#     which forwards aws.internal to the inbound endpoint → PHZ. (Set via user_data below.)
resource "aws_instance" "test" {
  for_each               = local.hosts
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [each.value.sg_id]
  iam_instance_profile   = local.instance_profile

  # Install dig; on the on-prem host also point resolv.conf at the dnsmasq server so aws.internal
  # lookups traverse on-prem → inbound → PHZ (the real on-prem-client experience).
  user_data = local.user_data[each.key]

  tags = { Name = "net-lab-r53-test-${each.key}" }
}
