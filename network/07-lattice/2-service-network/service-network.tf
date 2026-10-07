# The service network is the "mesh backplane": any VPC associated to it can resolve + reach any
# service associated to it (subject to auth). This is the piece that replaces peering/TGW routing.
#
# auth_type = AWS_IAM → every request is SigV4-signed and evaluated against the network's auth policy
# (and any per-service auth policy). NONE would make it open to all associated VPCs. We use IAM so the
# stretch 403 test is possible; the base network policy below allows all (we tighten per-service later).
resource "aws_vpclattice_service_network" "this" {
  name      = "net-lab-lattice"
  auth_type = "AWS_IAM"
}

# Network-level auth policy — allow-all here so the DEFAULT path works; the deny/allow decision for the
# stretch 403 test is done with a per-SERVICE auth policy in layer 3 (more specific, easier to reason).
# ⚠️ Verify live: a network policy is only evaluated when auth_type = AWS_IAM on the network.
resource "aws_vpclattice_auth_policy" "network" {
  resource_identifier = aws_vpclattice_service_network.this.arn
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

# Associate BOTH VPCs (A client, B service) to the network. Association is what injects the Lattice
# resolver + link-local data path into each VPC. The SG here is applied to the association's managed
# ENIs and gates traffic entering Lattice from that VPC (we allow HTTP:80).
resource "aws_vpclattice_service_network_vpc_association" "this" {
  for_each                   = local.vpc_ids
  vpc_identifier             = each.value
  service_network_identifier = aws_vpclattice_service_network.this.id
  security_group_ids         = [local.sg_ids[each.key]]
  tags                       = { Name = "net-lab-lattice-${each.key}" }
}
