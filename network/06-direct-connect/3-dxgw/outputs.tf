output "dx_gateway_id" { value = aws_dx_gateway.this.id }
output "dx_gateway_name" { value = aws_dx_gateway.this.name }
output "dxgw_amazon_side_asn" { value = var.dxgw_amazon_side_asn }

# The DXGW↔TGW association. In the console this shows up under Direct Connect → Direct Connect gateways
# → <this> → Gateway associations; verify via `aws directconnect describe-direct-connect-gateway-associations`.
output "dx_gateway_association_id" { value = aws_dx_gateway_association.tgw.dx_gateway_association_id }
output "dx_gateway_association_allowed_prefixes" { value = aws_dx_gateway_association.tgw.allowed_prefixes }
