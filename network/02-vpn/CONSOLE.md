# Lab 2 — Site-to-Site VPN → TGW: console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. Two of these steps aren't AWS
console clicks at all — they're software config on the strongSwan EC2 (step 7) — called out
clearly below so it's not confused with the AWS-side work.

## 1. Two VPCs
**VPC console → Your VPCs → Create VPC**:

| Name | CIDR |
|---|---|
| `net-lab-vpn-aws` | `10.10.0.0/16` |
| `net-lab-vpn-onprem` | `192.168.0.0/16` (simulated on-prem — deliberately far from `10.0.0.0/8`) |

## 2. One subnet + IGW + route table per VPC
`10.10.0.0/24` and `192.168.0.0/24`, auto-assign public IP, IGW attached, route table with
`0.0.0.0/0 → IGW` (needed both for SSM **and** so the strongSwan box's public IP can receive the
IPsec tunnels). **Don't add the cross-site routes yet** — come back after steps 4 and 7.

## 3. Security groups
**VPC console → Security groups → Create security group**:
- `net-lab-vpn-aws` (in the aws VPC) and `net-lab-vpn-onprem` (in the onprem VPC) — inbound ICMP
  from both `10.0.0.0/8` and `192.168.0.0/16`, egress all.
- `net-lab-vpn-strongswan` (in the onprem VPC, for the appliance only) — inbound **UDP 500**
  (IKE), **UDP 4500** (NAT-T), **protocol 50/ESP**, all from `0.0.0.0/0` (lab-grade — tighten to
  AWS's two tunnel IPs for anything beyond a lab, once you know them from step 5), plus the same
  ICMP rules as above.

## 4. Transit Gateway
**VPC console → Transit Gateways → Create transit gateway**:
- Name `net-lab-vpn`, Amazon side ASN **64512** (default)
- **Uncheck** default route table association/propagation — wired by hand below
- **Enable** ECMP support (lets both tunnels load-balance once both are up — stretch goal)

**Attach the aws VPC:** Transit Gateway attachments → Create → VPC attachment, VPC
`net-lab-vpn-aws`, its subnet.

**Route table:** Transit Gateway route tables → Create → `net-lab-vpn-main`. Associate the aws
VPC attachment to it, then **Propagations → Create propagation** for that same attachment (so the
VPN side can learn `10.10.0.0/16`).

**Back in the aws VPC's route table:** add `192.168.0.0/16 → Transit Gateway`.

## 5. Customer Gateway + VPN Connection
First, allocate a fixed public IP for the strongSwan box: **EC2 console → Elastic IPs → Allocate
Elastic IP address** (don't associate it yet — that happens in step 7 once the instance exists).

**VPC console → Customer gateways → Create customer gateway**:
- BGP ASN: `65000` (the on-prem side)
- IP address: the Elastic IP from above
- Type: Dynamic (BGP)

**VPC console → Site-to-Site VPN connections → Create VPN connection**:
- Target: **Transit Gateway** → `net-lab-vpn`
- Customer gateway: the one you just created
- Routing options: **Dynamic (requires BGP)**
- Leave tunnel options on **Amazon-generated** — AWS creates 2 tunnels, each with its own public
  endpoint IP, inside `/30` link (APIPA `169.254.x.x`), and pre-shared key.

**Associate the VPN's TGW attachment to the route table:** once created, this VPN connection
shows up as a 4th-ish attachment type. **Transit Gateway route tables → net-lab-vpn-main →
Associations → Create association** → pick the VPN attachment, then **Propagations → Create
propagation** for it too (this is what lets the aws VPC learn `192.168.0.0/16` once BGP comes up).

**Download the tunnel config:** select the VPN connection → **Download configuration** → vendor
**Generic**. You'll need the two tunnels' outside IPs, inside IPs, and PSKs for step 7.

## 6. SSM role + the strongSwan instance
IAM role `net-lab-ssm` (same as every other lab — trust EC2, attach
**AmazonSSMManagedInstanceCore**).

**EC2 console → Launch instance**: onprem VPC's subnet, `t4g.micro`, Amazon Linux 2023 arm64,
SG `net-lab-vpn-strongswan`, IAM role `net-lab-ssm`, no key pair. **Before launching**, open
**Advanced details → disable "Source/destination check"** — this box forwards packets that aren't
addressed to itself, which EC2 drops by default with the check on. (If you miss this at launch:
select the instance after → **Actions → Networking → Change source/destination check → Disable**.)

**Associate the Elastic IP** from step 5 to this instance (**Elastic IPs → select it → Actions →
Associate Elastic IP address**).

**Back in the onprem VPC's route table:** add `10.10.0.0/16 → this instance's ENI` (route target
"Network Interface", pick the strongSwan instance's primary ENI) — this is on-prem's "static route
to the VPN gateway."

## 7. ⚠️ Software config on the strongSwan box (not a console click)
**Session Manager into the strongSwan instance**, then:
```bash
sudo dnf install -y strongswan frr
```
Configure **strongSwan** (`/etc/ipsec.conf` + `/etc/ipsec.secrets`) with both tunnels' outside
IPs, inside IPs, and PSKs from the downloaded config in step 5 — `left`/`leftsubnet` =
`192.168.0.0/16` (onprem), `right` = each tunnel's AWS outside IP, `rightsubnet` =
`10.10.0.0/16`, auto=start.

Configure **FRR** (`/etc/frr/frr.conf`, enable `bgpd` in `/etc/frr/daemons`) to BGP-peer over each
tunnel's inside `/30` link: local ASN `65000`, neighbor = the tunnel's AWS-side inside IP, remote
ASN `64512`, advertise `network 192.168.0.0/16`.
```bash
sudo systemctl enable --now strongswan frr
sudo ipsec status        # both tunnels UP
sudo vtysh -c "show bgp summary"   # BGP session Established, prefix count > 0
```
Once BGP is up, check the VPN connection's **Tunnel details** tab in the console — both tunnels
should show **UP**, and the TGW route table should show a propagated `192.168.0.0/16` route.

## 8. Test EC2 (both sides)
One `t4g.micro` in each VPC's subnet, same SSM role + that VPC's own SG (not the strongswan SG).

## 9. Verify
**Session Manager into the aws-side test host:**
```bash
ping <onprem test host private IP>   # routes: aws → TGW → VPN → strongSwan → onprem host
```
**Session Manager into the onprem-side test host:**
```bash
ping <aws test host private IP>
```

## Stretch
- **BGP failover:** on the strongSwan box, `sudo systemctl stop strongswan` (or just the FRR
  session) to kill tunnel 1 — watch the VPN connection's Tunnel details show one DOWN, and time how
  long pings take to recover once BGP reconverges onto tunnel 2.
- **ECMP:** with both tunnels UP and ECMP enabled on the TGW (step 4), traffic should load-balance
  across both — generate multiple flows and check they don't all pin to one tunnel.
- **MTU/PMTUD:** `ping -M do -s 1372 <peer IP>` from a test host — VPN's effective path MTU is
  lower than plain IP (IPsec overhead), expect usable payload around 1379 bytes before
  fragmentation; add MSS clamping if TCP sessions stall.

## Clean up
EC2 instances → disassociate + release the Elastic IP → VPN connection → customer gateway → TGW
route table → TGW attachments → Transit Gateway → route table entries → IGWs → subnets → VPCs →
the `net-lab-ssm` IAM role.
