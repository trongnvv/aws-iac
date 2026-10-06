# The simulated on-prem DNS server. Pinned to a STATIC private IP (var.onprem_dns_ip) so layer 2-dns's
# outbound forwarding rule can target it before this host exists — the core ordering trick of the lab.
resource "aws_instance" "dns" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.onprem_subnet_id
  private_ip             = var.onprem_dns_ip # fixed → forwarding-rule target is known in advance
  vpc_security_group_ids = [local.onprem_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  # Inbound endpoint IPs are templated in so dnsmasq forwards *.aws.internal to the AWS resolver.
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    inbound_ips   = local.inbound_ips
    onprem_dns_ip = var.onprem_dns_ip
  })

  tags = { Name = "net-lab-r53-onprem-dns" }
}
