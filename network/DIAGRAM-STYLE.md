# Diagram style — AWS specifics

AWS-only conventions for the `architecture.py` infographics (one per lab). The **generic** diagram
mechanics (framework, structure, legend, verdict/contrast/hero rules, render process) live in the
vault note `01_Knowledge/System-Design/Diagram-As-Code.md`. This file is **only** the AWS-specific part.

## 1. Name the AWS resource, NOT the Terraform resource
Cards and labels read like the **AWS console**, not the HCL. The diagram shows the architecture that
exists in AWS, not the code that made it.

| ✅ Use (AWS object) | ❌ Avoid (Terraform) |
|---|---|
| VPC · Subnet · Internet Gateway · NAT Gateway | `aws_vpc.this["a"]` · `aws_subnet` · `aws_nat_gateway` |
| Route table → route `0.0.0.0/0 → Internet Gateway` | `aws_route_table` · `aws_route` |
| VPC Peering Connection (pcx a-b) | `aws_vpc_peering_connection.a_b` |
| Transit Gateway · TGW attachment · TGW route table | `aws_ec2_transit_gateway*` |
| Interface VPC Endpoint (ENI) · Endpoint Service | `aws_vpc_endpoint` · `aws_vpc_endpoint_service` |
| Lattice Service Network · Service · Target group | `aws_vpclattice_*` |
| Customer Gateway · Site-to-Site VPN · DX Gateway / Transit VIF | `aws_customer_gateway` · `aws_vpn_connection` · `aws_dx_*` |
| Route 53 Resolver inbound/outbound endpoint · Private Hosted Zone | `aws_route53_resolver_*` |
| EC2 instance · Security Group · IAM role + instance profile | `aws_instance` · `aws_security_group` · `aws_iam_role` |

Keep real values where they help (CIDRs `10.0.0.0/24`, `pcx a-b`, port 80, ASN 64512). Avoid `.this[...]`,
`for_each` keys, and module paths.

## 2. AWS vocabulary per lab (what each diagram should surface)
- **TGW (lab 1):** Transit Gateway · VPC attachment (+ which subnet holds the ENI) · 2 TGW route tables
  (association vs propagation) · NAT Gateway · Internet Gateway.
- **VPN (lab 2) / DX (lab 6):** Customer Gateway · Site-to-Site VPN (2 tunnels) · BGP ASNs · TGW ·
  DX Gateway · Transit VIF (DX only; mark the physical cross-connect as the manual step).
- **PrivateLink (lab 3):** Endpoint Service (NLB-backed) · Interface VPC Endpoint = an **ENI that
  terminates the client's TCP** · overlapping CIDR OK.
- **Resolver (lab 4):** Resolver inbound/outbound endpoints (ENIs, 2 AZs) · forwarding rule · Private
  Hosted Zone · on-prem DNS. Split DNS vs IP.
- **Peering (lab 5):** VPC Peering Connection ×2 · routes both ways · the non-transitive B⊥C gap.
- **Lattice (lab 7):** Service Network · Service · Target group · Listener · IAM auth policy · Lattice
  DNS name → link-local 169.254.x (L7, not routing).

## 3. `diagrams` icon mapping (known-good classes)
`from diagrams.aws.compute import EC2Instance, EKS, ECR` · `management import SystemsManager` ·
`security import IAMRole, IAMPermissions, SecretsManager` ·
`network import InternetGateway, NATGateway, PublicSubnet, PrivateSubnet, RouteTable, TransitGateway,
TransitGatewayAttachment, VPCPeering, VPCElasticNetworkInterface, Endpoint, Privatelink,
ElbNetworkLoadBalancer, ELB, Route53, Route53HostedZone, SiteToSiteVpn, VPCCustomerGateway, DirectConnect`.

No native icon → use a **letter badge** (`card(..., letter="L")`), not a misleading stand-in:
- VPC Lattice Service Network / Service → badge `L` (NOT `ELB` — reads as a load balancer).
- Lattice DNS name → badge `⬡`. HTTP listener → badge `L`.
- Resolver endpoint → `VPCElasticNetworkInterface` (it is an ENI) is acceptable.

## 4. AWS gotchas worth showing in the diagram (not just text)
- **Lattice target SG** must allow the **VPC Lattice managed prefix list** (`com.amazonaws.<region>.vpc-lattice`),
  NOT the client/VPC CIDR — else the target is UNHEALTHY. (Fixed in lab 7 IaC.)
- **Interface endpoint** is an **ENI that terminates TCP** (a "mini-server" in the consumer VPC) → its SG
  needs **ingress** from the consumer; the consumer host only needs egress.
- **TGW attachment subnet_ids** = where the ENI sits; the whole VPC still uses the attachment. Keep the
  TGW ENI in a dedicated subnet so its route table can carry egress `0/0 → NAT` independently.
- **Implicit local route** (VPC CIDR → local) is always present and wins intra-VPC; never drawn as a
  resource but worth a note where it explains "same-VPC always reachable".
- **DX** physical cross-connect + Transit VIF = the one manual/partner step (can't be IaC'd); mark it ⚠.

## 5. Render
```bash
cd <lab>  # e.g. 05-peering
uv run --native-tls --with diagrams python architecture.py   # → architecture.png
```
Needs graphviz (`brew install graphviz`) and `--native-tls` (corporate CA). `python3 -m py_compile
architecture.py` checks syntax without the lib.
