# --- The service itself (VPC A) ---
# A tiny HTTP server on :80. A systemd unit runs python3's http.server serving a one-line page, so a
# consumer curl returns proof-of-reach text. SSM-managed, no SSH.
resource "aws_instance" "service" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.subnet_a
  vpc_security_group_ids = [local.svc_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = <<-EOF
    #!/bin/bash
    # Serve a fixed page so the consumer can prove it reached THIS host across the overlapping CIDR.
    mkdir -p /opt/www
    echo "hello from PrivateLink provider (VPC A) $(hostname)" > /opt/www/index.html
    cat >/etc/systemd/system/labhttp.service <<'UNIT'
    [Unit]
    Description=Lab HTTP service
    After=network.target
    [Service]
    WorkingDirectory=/opt/www
    ExecStart=/usr/bin/python3 -m http.server 80
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now labhttp
  EOF

  tags = { Name = "net-lab-pl-service" }
}

# --- Internal NLB fronting the service (VPC A) ---
# PrivateLink can only publish an NLB (or GWLB). It's internal — no public exposure; the only way in is
# the endpoint service.
resource "aws_lb" "service" {
  name               = "net-lab-pl-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [local.subnet_a]
  tags               = { Name = "net-lab-pl-nlb" }
}

resource "aws_lb_target_group" "service" {
  name        = "net-lab-pl-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = local.vpc_a_id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "80"
  }
  tags = { Name = "net-lab-pl-tg" }
}

resource "aws_lb_target_group_attachment" "service" {
  target_group_arn = aws_lb_target_group.service.arn
  target_id        = aws_instance.service.id
  port             = 80
}

resource "aws_lb_listener" "service" {
  load_balancer_arn = aws_lb.service.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }
}

# --- VPC Endpoint Service = the PrivateLink publication ---
# acceptance_required=false so the consumer can connect without a manual approval handshake (fine for a
# lab; in prod with unknown consumers you'd require acceptance). This yields a service name like
# com.amazonaws.vpce.ap-southeast-1.vpce-svc-xxxx that the consumer uses to create its interface endpoint.
resource "aws_vpc_endpoint_service" "service" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.service.arn]
  tags                       = { Name = "net-lab-pl-endpoint-service" }
}
