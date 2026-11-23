# Lab 4 — Route 53 Resolver (hybrid DNS): console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. Proves **two-way hybrid DNS**:
AWS → on-prem (`*.corp.local`) and on-prem → AWS (`*.aws.internal`). Self-contained — builds its
own simulated on-prem, no dependency on Lab 2.

## 1. Two VPCs + peering
**VPC console → Your VPCs → Create VPC**:

| Name | CIDR |
|---|---|
| `net-lab-r53-aws` | `10.20.0.0/16` (2 AZ subnets) |
| `net-lab-r53-onprem` | `192.168.0.0/16` (1 subnet) |

Subnets: two in the aws VPC (`10.20.0.0/24`, `10.20.1.0/24`, one per AZ — Resolver endpoints need
2 AZs), one in the onprem VPC (`192.168.0.0/24`). IGW + route table (`0.0.0.0/0 → IGW`) on each,
for SSM.

**Peering connection:** `net-lab-r53-aws` ↔ `net-lab-r53-onprem`, auto-accept (same account).
**Routes, both sides:** aws VPC's route table → `192.168.0.0/16 → the peering connection`; onprem
VPC's route table → `10.20.0.0/16 → the peering connection`. The peering link is just the path for
the DNS *packets* (UDP/TCP 53) — the actual name resolution logic is all in steps 2–3.

## 2. Security groups
- `net-lab-r53-inbound` (aws VPC, for the Resolver inbound endpoint) — inbound **UDP 53 and TCP
  53** from `192.168.0.0/16` (on-prem's dnsmasq forwards `aws.internal` queries here), egress all.
- `net-lab-r53-outbound` (aws VPC, for the Resolver outbound endpoint) — egress **UDP 53 and TCP
  53** to `192.168.0.0/16` (that's the direction that matters for this one).
- A general-purpose SG per VPC for the test/dnsmasq hosts — ICMP + DNS 53 both directions, egress all.

## 3. AWS side — private hosted zone
**Route 53 console → Hosted zones → Create hosted zone**:
- Domain name: `aws.internal`
- Type: **Private hosted zone**
- VPCs to associate: `net-lab-r53-aws`

**Add a test record:** inside the zone → **Create record** → name `test`, type **A**, value
`10.20.99.99` (a dummy IP — this lab proves *resolution*, not reachability of that address).

## 4. AWS side — Resolver endpoints
**Route 53 console → Resolver → Inbound endpoints → Create inbound endpoint**:
- Name `net-lab-r53-inbound`, VPC `net-lab-r53-aws`, SG `net-lab-r53-inbound`
- IP addresses: one per AZ subnet (both of them) — this gives on-prem 2 fixed IPs to forward
  `aws.internal` queries to.

**Resolver → Outbound endpoints → Create outbound endpoint**:
- Name `net-lab-r53-outbound`, VPC `net-lab-r53-aws`, SG `net-lab-r53-outbound`
- Same 2 AZ subnets.

**Resolver → Rules → Create rule**:
- Name `net-lab-r53-corp-local`, type **Forward**
- Domain name: `corp.local`
- Outbound endpoint: `net-lab-r53-outbound`
- Target IP: the on-prem dnsmasq's fixed IP (pick one now, e.g. `192.168.0.53` — you'll assign
  this exact IP to the dnsmasq instance in step 5)
- **Associate VPC:** `net-lab-r53-aws` — this is what makes AWS hosts automatically use the rule
  for `*.corp.local` queries.

## 5. On-prem side — dnsmasq (software config, not a console click)
**EC2 console → Launch instance**, onprem VPC's subnet, `t4g.micro`, Amazon Linux 2023 arm64, the
`net-lab-ssm` IAM role (create it first if you haven't — trust EC2, attach
**AmazonSSMManagedInstanceCore**), the general-purpose onprem SG, no key pair. **Private IP: set
it explicitly** to the same IP you put in the Resolver rule's target (e.g. `192.168.0.53`) —
**Advanced details → Network interface → Private IP**.

**Session Manager in**, install + configure dnsmasq:
```bash
sudo dnf install -y dnsmasq
```
Configure `/etc/dnsmasq.conf` to:
- be authoritative for `corp.local` (add local test records, e.g. `host1.corp.local` → some IP)
- forward anything under `aws.internal` to the two inbound-endpoint IPs from step 4:
  `server=/aws.internal/<inbound-ip-1>` and `server=/aws.internal/<inbound-ip-2>`
```bash
sudo systemctl enable --now dnsmasq
```

## 6. Test hosts
One `t4g.micro` in each VPC's subnet, same SSM role, each VPC's general-purpose SG, no key pair.
The **onprem** test host's DNS needs to point at the dnsmasq box — either set it as the VPC's DHCP
option set's domain-name-servers, or just `dig @192.168.0.53 ...` explicitly in the verify step.

## 7. Verify
**Session Manager into the aws test host:**
```bash
dig host1.corp.local        # AWS's default resolver sees the corp.local rule → forwards to dnsmasq
```
**Session Manager into the onprem test host (or SSM into dnsmasq itself):**
```bash
dig @192.168.0.53 test.aws.internal   # dnsmasq forwards aws.internal → inbound endpoint → PHZ
```
Both should resolve — two-way hybrid DNS working across the peering link.

## Stretch
- **Two-way, explicitly:** confirm both directions independently (the verify step above already
  does this) — AWS→on-prem via the outbound endpoint + forwarding rule, on-prem→AWS via dnsmasq +
  the inbound endpoint + PHZ.
- **Reverse DNS (PTR):** add a PTR-capable zone or dnsmasq PTR entry for one of the lab's private
  IPs and confirm `dig -x <ip>` resolves it from both sides.

## Clean up
Test hosts + dnsmasq instance → Resolver rule (disassociate the VPC first) → inbound/outbound
endpoints → private hosted zone → peering connection → route table entries → IGWs → subnets →
VPCs → the `net-lab-ssm` IAM role.
