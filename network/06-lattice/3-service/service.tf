# --- Target service EC2 in VPC B ------------------------------------------------------------------
# Tiny HTTP server via user_data (Python one-liner on :80). SSM-managed so we can shell in if needed.
# This instance is what the Lattice target group registers; the client in VPC A never sees its IP.
resource "aws_instance" "service" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t4g.micro"
  subnet_id              = local.subnet_b_id
  vpc_security_group_ids = [local.sg_b_id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  # Serve a fixed body on / (and distinct bodies on /v1, /v2 for the path-routing stretch).
  user_data = <<-EOF
    #!/bin/bash
    mkdir -p /srv/www/v1 /srv/www/v2
    echo "hello from service B (VPC B, CIDR 10.0.0.0/16) - default" > /srv/www/index.html
    echo "service B /v1 response" > /srv/www/v1/index.html
    echo "service B /v2 response" > /srv/www/v2/index.html
    cd /srv/www && nohup python3 -m http.server 80 >/var/log/httpd.log 2>&1 &
  EOF

  tags = { Name = "net-lab-lattice-service-b" }
}

# --- Lattice target group (type INSTANCE) -----------------------------------------------------------
# config.vpc_identifier scopes the TG to VPC B. Health check hits / on :80.
# ⚠️ Verify live: for type = INSTANCE the config block requires port/protocol/vpc_identifier.
resource "aws_vpclattice_target_group" "this" {
  name = "net-lab-lattice-b"
  type = "INSTANCE"

  config {
    port             = 80
    protocol         = "HTTP"
    protocol_version = "HTTP1"
    vpc_identifier   = local.vpc_b_id

    health_check {
      enabled  = true
      path     = "/"
      port     = 80
      protocol = "HTTP"
      matcher {
        value = "200"
      }
    }
  }
}

# Register the service instance into the TG. target.id = instance id, target.port = 80.
resource "aws_vpclattice_target_group_attachment" "this" {
  target_group_identifier = aws_vpclattice_target_group.this.id
  target {
    id   = aws_instance.service.id
    port = 80
  }
}

# --- Lattice service (the thing with the DNS name) --------------------------------------------------
# auth_type = AWS_IAM so we can attach a per-service auth policy (stretch 403). The service gets an
# AWS-generated DNS name like <name>-<suffix>.<id>.vpc-lattice-svcs.<region>.on.aws — that is what the
# client curls. Overlapping CIDR is irrelevant: the name resolves to a link-local Lattice address.
resource "aws_vpclattice_service" "this" {
  name      = "net-lab-lattice-svc-b"
  auth_type = "AWS_IAM"
}

# Per-service auth policy. Allow-all keeps the CORE test green. For the stretch 403 test, swap the
# Principal to a specific role ARN (or add a deny) so an unauthorized client is rejected at the edge.
# ⚠️ Verify live: policy is on the SERVICE arn; action vpc-lattice-svcs:Invoke.
resource "aws_vpclattice_auth_policy" "service" {
  resource_identifier = aws_vpclattice_service.this.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "vpc-lattice-svcs:Invoke"
      Resource  = "*"
    }]
  })
}

# HTTP:80 listener. Default action forwards 100% to the TG. For the path-routing stretch, add
# aws_vpclattice_listener_rule resources matching /v1 and /v2 to separate target groups.
resource "aws_vpclattice_listener" "http" {
  name               = "http"
  service_identifier = aws_vpclattice_service.this.id
  protocol           = "HTTP"
  port               = 80

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this.id
        weight                  = 100
      }
    }
  }
}

# Attach the service to the network — THIS is what publishes the service to every associated VPC.
# Without it, the service exists but no VPC can resolve/reach it.
resource "aws_vpclattice_service_network_service_association" "this" {
  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = local.service_network_id
}
