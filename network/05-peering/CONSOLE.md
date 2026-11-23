# Lab 5 — VPC Peering vs TGW: console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. A = hub, peers with both B and
C; **B and C are never peered with each other** — proving peering is non-transitive (contrast
Lab 1's TGW, which is transitive by design).

## 1. Three VPCs
**VPC console → Your VPCs → Create VPC** (VPC only):

| Name | CIDR |
|---|---|
| `net-lab-peer-a` | `10.0.0.0/16` |
| `net-lab-peer-b` | `10.1.0.0/16` |
| `net-lab-peer-c` | `10.2.0.0/16` |

## 2. One subnet + IGW + route table per VPC
Same pattern 3×, one per VPC:
- **Subnets → Create subnet**: `10.x.0.0/24`, one AZ (use the same AZ for all three), enable
  **auto-assign public IPv4**.
- **Internet gateways → Create** → **Attach to VPC**.
- **Route tables → Create route table**, associate to that VPC's subnet, add `0.0.0.0/0 → IGW`.
- Default security group is fine for this lab (or create one allowing ICMP from `10.0.0.0/8`,
  egress all — same pattern as Lab 1 if you want it explicit).

## 3. Two peering connections (hub-and-spoke around A)
**VPC console → Peering connections → Create peering connection**:

| Name | Requester VPC | Accepter VPC |
|---|---|---|
| `net-lab-peer-a-b` | `net-lab-peer-a` | `net-lab-peer-b` (same account/region) |
| `net-lab-peer-a-c` | `net-lab-peer-a` | `net-lab-peer-c` |

Same account + same region → the connection auto-completes without a separate accept step from
the console's perspective, but double-check each one's status is **Active** (select it →
**Actions → Accept request** if it's still "Pending acceptance").

**Do not create a B↔C peering connection** — that's the point.

## 4. Routes — both sides, every time
Peering carries no traffic until BOTH route tables involved have an explicit route. **VPC console
→ Route tables → [table] → Routes tab → Edit routes → Add route**:

| Route table | Destination | Target |
|---|---|---|
| A's | `10.1.0.0/16` | `net-lab-peer-a-b` |
| A's | `10.2.0.0/16` | `net-lab-peer-a-c` |
| B's | `10.0.0.0/16` | `net-lab-peer-a-b` |
| C's | `10.0.0.0/16` | `net-lab-peer-a-c` |

**Deliberately skip:** any route in B pointing to C, or in C pointing to B. There's also no
B↔C peering connection to route through even if you tried — that's what makes this non-transitive.

## 5. SSM role + test EC2
Same as Lab 1 steps 10–11: one IAM role `net-lab-ssm` (trust EC2, attach
**AmazonSSMManagedInstanceCore**), then launch one `t4g.micro` (Amazon Linux 2023, arm64, no key
pair, that role) in each VPC's subnet.

## 6. Verify
**Session Manager into the A instance:**
```bash
ping <B private IP>   # OK — A↔B peered + routed
ping <C private IP>   # OK — A↔C peered + routed
```
**Session Manager into the B instance:**
```bash
ping <C private IP>   # times out — no peering connection, no route either way
```

## Stretch — measure it
- **Latency + cost:** ping A↔B a few times, note the latency (same-AZ peering ≈ sub-ms; cross-AZ
  peering is $0.01/GB — check **VPC console → Peering connections → [connection] → Details** for
  the AZs each side's subnet sits in).
- **MTU:** `ping -M do -s 8973 <peer private IP>` from a test host — VPC Peering supports jumbo
  frames (9001 MTU) within a region; TGW tops out at 8500, VPN around 1500 (minus IPsec overhead).

## Clean up
EC2 instances → route table entries referencing the peering connections → peering connections →
route tables → IGWs (detach first) → subnets → VPCs → the `net-lab-ssm` IAM role.
