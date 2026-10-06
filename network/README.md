# Network connectivity — test plan

> Code: `~/src/github/trongnvv/aws-iac/network/` (OpenTofu · provider profile `default`).
> Concept / trade-offs / decision map: workbook `01_Knowledge/Network/Cloud-Connectivity/Concept.md`.

Priority order — **most necessary first**. Each lab has **Core** (must pass to call it done) and
**Stretch** (senior-grade: failure modes, scale, edge cases, measured trade-offs). Do Core first,
Stretch if time. No real DC/DX → **on-prem is simulated by a separate VPC + an EC2 running
strongSwan/libreswan** as the Customer Gateway. Write the per-lab note after finishing.

**Per-lab convention:** each lab is **layered** IaC (numbered subfolders — e.g. `1-vpc/ 2-tgw/ 3-ssm/
4-ec2/` — each its own state, + `deploy.sh`/`teardown.sh`), and its README carries an **architecture
diagram + test scenario + troubleshooting + the test-EC2 recipe** (`t4g.micro` + SSM, no SSH).

| # | Lab | Solves (traffic) | Core goal | On-prem sim |
|---|---|---|---|---|
| **1** | TGW hub + segmentation (+ optional egress) | **AWS↔AWS** — many VPCs (>10), hub + segment prod/dev · *opt:* **AWS→Internet** central egress | 3 VPCs via TGW; prod↔shared, dev↔shared, **prod⊥dev** · opt. one NAT in shared | — |
| **2** | Site-to-Site VPN → TGW | **AWS↔on-prem** — hybrid over public Internet, encrypted | on-prem ↔ VPC over IPsec + BGP | VPC + strongSwan |
| **3** | PrivateLink | **AWS↔3rd-party/vendor** — overlapping CIDR / expose one app only | share one service; overlapping CIDR still works | — |
| **4** | Route 53 Resolver | **AWS↔on-prem** — hybrid DNS (the glue: `.corp` ↔ `.aws`) | two-way hybrid DNS | reuse lab-2 on-prem |
| **5** | VPC Peering vs TGW | **AWS↔AWS** — few VPCs (<5–10), the cheap alternative to TGW | non-transitive + measured trade-offs | — |
| **6** | VPC Lattice | **AWS↔AWS (L7, service-to-service)** — app-layer connectivity across VPCs/accounts, no routing/CIDR coupling | service network + 2 services across VPCs; overlapping CIDR OK; path/header routing + IAM auth | — |

> **Out of scope (noted for completeness):** User↔AWS remote access (WFH) = **AWS Client VPN** (OpenVPN)
> or **AWS Verified Access** (zero-trust / identity-based); **Direct Connect** = concept-only (no physical
> port). These labs cover the AWS↔AWS (L3 + L7), AWS↔on-prem, and AWS↔vendor traffic classes end-to-end.

---

## Lab 1 — TGW hub + segmentation  (`01-tgw-hub/`)
```mermaid
graph LR
  subgraph shared["VPC shared 10.0/16"]
    s["subnet /24 · EC2 (SSM)"]
  end
  subgraph prod["VPC prod 10.1/16"]
    p["subnet /24 · EC2"]
  end
  subgraph dev["VPC dev 10.2/16"]
    d["subnet /24 · EC2"]
  end
  subgraph tgw["Transit Gateway"]
    srt["shared-rt &rarr; learns prod+dev"]
    krt["spoke-rt &rarr; learns shared only"]
  end
  s -->|attach| srt
  p -->|attach| krt
  d -->|attach| krt
  p -. "prod &perp; dev (no route)" .- d
```
- **Core:** 3 VPC + TGW + 2 TGW route tables. `shared` reaches prod + dev; `prod`/`dev` reach shared
  but **not each other**. Prove by SSM + ping (shared→both OK; prod→dev times out).
- **Stretch:**
  - [ ] **Blackhole route** on the spoke route table to *actively drop* prod↔dev, and compare with the
        implicit no-route case (blackhole = explicit + auditable + overrides a propagated route).

### Lab 1 · optional — centralized egress (layer `5-egress/`, `enable_egress=true`)
Folded into lab 1 (not a separate lab). Off by default (segmentation stays NAT-free). The shared VPC
is **egress-ready** — its TGW attachment sits in a dedicated subnet — so turning this on only adds a
NAT + routes + spoke private subnets, no rework.
```mermaid
graph LR
  subgraph prod["VPC prod"]
    p["private subnet<br/>EC2 (no IGW)"]
  end
  subgraph dev["VPC dev"]
    d["private subnet<br/>EC2 (no IGW)"]
  end
  subgraph shared["VPC shared"]
    tsub["TGW subnet<br/>RT: 0/0 &rarr; NAT"]
    nat["NAT GW (public subnet)"]
    igw[IGW]
  end
  p -->|"0/0 &rarr; TGW"| tgw{{"TGW<br/>spoke-RT: 0/0 &rarr; shared"}}
  d -->|"0/0 &rarr; TGW"| tgw
  tgw --> tsub --> nat --> igw --> net((Internet))
```
- **Enable:** `(cd 01-tgw-hub/5-egress && tofu apply -var enable_egress=true)`.
- **What:** spokes get a **private subnet (no IGW)**; `0/0 → TGW → shared's NAT → IGW`. One NAT serves
  all VPCs (the enterprise pattern — vs a NAT per VPC).
- **Verify:** SSM into a spoke **private** host (its agent reaches AWS *through* the central NAT) →
  `curl -s https://checkip.amazonaws.com` returns the **shared VPC's NAT EIP** (`tofu output nat_public_ip`).
- Note: NAT Gateway ≈ $0.045/hour + data — `(cd 5-egress && tofu destroy)` after.

## Lab 2 — Site-to-Site VPN → TGW
```mermaid
graph LR
  subgraph onprem["'On-prem' VPC 192.168/16"]
    cgw["strongSwan EC2<br/>Customer GW · BGP ASN 65000"]
  end
  subgraph aws["AWS"]
    tgw{{"TGW · ASN 64512"}} --- shared["VPC shared 10.0/16"]
  end
  cgw ==>|"Tunnel 1 — IPsec + BGP"| tgw
  cgw ==>|"Tunnel 2 — standby / ECMP"| tgw
```
- **Core:** "on-prem" VPC + strongSwan EC2 as Customer Gateway; IPsec VPN + **BGP** into the TGW;
  ping on-prem ↔ cloud VPC both ways.
- **Stretch:**
  - [ ] **BGP failover/convergence:** drop tunnel 1 (stop IPsec/BGP) → measure time to fail over to tunnel 2.
  - [ ] **ECMP:** enable ECMP on the TGW → confirm traffic load-balances across both tunnels.
  - [ ] **MTU / PMTUD:** `ping -M do -s <size>` (DF bit) to find the working MSS; VPN path ≈ **1500**
        (IPsec overhead → effective MSS ≈ 1379) → add **MSS clamping**; confirm no fragmentation.

## Lab 3 — PrivateLink
```mermaid
graph LR
  subgraph B["VPC B (consumer) 10.0/16"]
    c[client] --> ep["Interface Endpoint<br/>ENI + private DNS name"]
  end
  subgraph A["VPC A (provider) 10.0/16 — CIDR overlaps!"]
    nlb[NLB] --> svc["service EC2 :app"]
  end
  ep ==>|"PrivateLink (endpoint service)"| nlb
```
- **Core:** NLB-backed service in VPC A → interface endpoint in VPC B; **overlapping CIDR still works**
  (traffic is to the endpoint ENI, not routed between CIDRs).
- **Stretch:**
  - [ ] **Private DNS name:** enable it → the endpoint resolver overrides the service's domain to the
        endpoint's **private IP** (consumer uses the real service DNS name transparently).
  - [ ] **Cross-zone LB:** consumer in AZ-a reaches a target in AZ-b (toggle NLB cross-zone; note the
        cross-AZ data fee).

## Lab 4 — Route 53 Resolver (hybrid DNS)
```mermaid
graph LR
  subgraph aws["AWS VPC"]
    out["Resolver OUTBOUND EP"]
    inb["Resolver INBOUND EP"]
    phz["Route53 PHZ<br/>aws.internal"]
  end
  subgraph onprem["On-prem"]
    dns["corp DNS<br/>corp.local"]
  end
  out -->|"query *.corp.local"| dns
  dns -->|"query *.aws.internal"| inb --> phz
```
- **Core:** inbound + outbound endpoints + resolver rules.
- **Stretch:**
  - [ ] **Two-way:** AWS→on-prem resolve `*.corp.local` via the **outbound** endpoint; on-prem→AWS
        resolve `*.aws.internal` via the **inbound** endpoint → Route 53 private hosted zone.
  - [ ] **Reverse DNS (PTR):** verify PTR lookups of internal IPs both directions.

## Lab 5 — VPC Peering vs TGW (trade-offs & limits)
```mermaid
graph LR
  A["VPC A 10.0/16"] ---|"Peering A-B + routes"| B["VPC B 10.1/16"]
  A ---|"Peering A-C + routes"| C["VPC C 10.2/16"]
  B -. "B&harr;C: no peering, no route<br/>(non-transitive)" .- C
```
- **Core:** 2 VPCs peered; show **non-transitive** (A↔B, A↔C, but B can't reach C via A).
- **Stretch (measured):**
  - [ ] **Latency + cost:** ping latency + data cost — Peering (**same-AZ free, cross-AZ $0.01/GB**) vs
        TGW (**$0.05/attachment-hour + $0.02/GB** processing).
  - [ ] **MTU:** jumbo **9001** on Peering (intra-region) vs **8500** max over TGW vs **~1500** over VPN.

## Lab 6 — VPC Lattice (L7 service-to-service)
```mermaid
graph LR
  subgraph net["Lattice Service Network (+ IAM auth policy)"]
    svcA["Service A<br/>(VPC A)"]
    svcB["Service B<br/>(VPC B, CIDR overlaps)"]
  end
  cA["client (VPC A)"] -->|"https://svc-b.<br/>…lattice (path/header routing)"| svcB
  vpcA[VPC A] -.associated.- net
  vpcB[VPC B] -.associated.- net
```
Different from everything above: **L7 (HTTP/gRPC), not L3 routing**. No route tables, no CIDR planning —
a client reaches a service by its Lattice DNS name; Lattice handles discovery, routing (path/header),
and **IAM-based auth** between services. Overlapping CIDRs are a non-issue (it's not routed at L3).
- **Core:** one **service network**; associate VPC A + VPC B to it; register **Service A** (target =
  EC2/ALB in VPC A) and **Service B** in VPC B. A client in VPC A calls Service B by its Lattice DNS
  name and gets a response — **even with overlapping CIDRs**, no peering/TGW.
- **Stretch:**
  - [ ] **Path/header routing:** one listener → rules routing `/v1` vs `/v2` (or a header) to different
        target groups (the L7 feature TGW/PrivateLink can't do).
  - [ ] **Auth policy (IAM):** attach a service auth policy that only allows a specific principal/VPC →
        a call from an unauthorized client gets **403** (zero-trust service-to-service).
  - [ ] **vs PrivateLink/TGW:** note the trade — Lattice = managed L7 mesh-lite, per-request + data cost,
        newer; PrivateLink = L4 one-service expose; TGW = L3 bulk routing.

---

## Direct Connect — concept-only (no physical port to lab)
Theory + console walkthrough; closest simulation is VPN-over-TGW (lab 2). VIF map → see the Concept doc.

**Why this order:** TGW is the real-world backbone (#1, with centralized egress as its optional add-on)
→ VPN to on-prem is the most common hybrid need (#2) → PrivateLink solves share-a-service +
overlapping-CIDR (#3) → hybrid DNS comes with on-prem (#4) → Peering as the cheap few-VPC alternative
to TGW (#5) → VPC Lattice last: the L7/service-mesh angle on AWS↔AWS, newer and app-layer rather than
routing (#6).
