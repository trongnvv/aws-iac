# Client host in VPC A. SSM into it, then `curl http://<service_dns_name>` — the request reaches the
# service in VPC B through the Lattice service network, despite A and B sharing CIDR 10.0.0.0/16 and
# having no peering/TGW. The service DNS name is baked into a motd so it is visible on login.
resource "aws_instance" "client" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.subnet_a_id
  vpc_security_group_ids = [local.sg_a_id]
  iam_instance_profile   = local.instance_profile

  user_data = <<-EOF
    #!/bin/bash
    echo "Lattice service DNS: ${local.service_dns_name}" > /etc/motd
    echo "Try: curl http://${local.service_dns_name}"    >> /etc/motd
  EOF

  tags = { Name = "net-lab-lattice-client-a" }
}
