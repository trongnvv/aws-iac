# Consumer test host in VPC B. SSM into it and `curl http://<endpoint-dns>` — it reaches the service in
# VPC A despite both VPCs using 10.0.0.0/16, because the request goes to the endpoint ENI's IP (in B)
# and PrivateLink carries it to the NLB (in A). The endpoint DNS name is baked into the login banner so
# you can copy-paste it after `start-session`.
resource "aws_instance" "consumer" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.subnet_b
  vpc_security_group_ids = [local.consumer_sg_id]
  iam_instance_profile   = local.instance_profile

  user_data = <<-EOF
    #!/bin/bash
    echo "PrivateLink test: curl http://${local.endpoint_dns_name}" > /etc/motd
  EOF

  tags = { Name = "net-lab-pl-consumer" }
}
