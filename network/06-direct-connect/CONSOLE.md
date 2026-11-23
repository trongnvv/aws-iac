# Lab 6 — Direct Connect → TGW: console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. This lab is **[`02-vpn`'s
walkthrough](../02-vpn/CONSOLE.md) plus one new layer** (the DX Gateway control plane) — do that
one first if you haven't, the pattern here assumes you've seen it. Differences only, below.

**Why there's still a VPN in a "Direct Connect" lab:** a real DX needs a physical cross-connect at
a DX location via a partner — that one step genuinely cannot be done from a console, by hand, or
any other way without a real line ordered from a real provider. This lab builds the **DX-as-code
control plane** for real (DX Gateway + its TGW association), and uses the Site-to-Site VPN as the
**documented "DX + VPN" transport stand-in** so the data path actually works end to end.

## 1–2. VPCs + subnets — same pattern, different CIDRs
Two VPCs: `net-lab-dx-aws` (`10.30.0.0/16`) and `net-lab-dx-onprem` (`192.168.30.0/16`) —
deliberately different from Lab 2's `10.10.0.0/16`/`192.168.0.0/16` so both labs can exist at the
same time without clashing. Same subnet/IGW/route-table steps as Lab 2 steps 1–2.

## 3. Security groups — identical pattern
`net-lab-dx-aws`, `net-lab-dx-onprem` (ICMP from both CIDRs), `net-lab-dx-strongswan` (IKE/NAT-T/
ESP from `0.0.0.0/0` + ICMP) — same as Lab 2 step 3, just named for this lab.

## 4. Transit Gateway — same pattern, new TGW
`net-lab-dx` hub, uncheck default assoc/propagation, enable ECMP. Attach the aws VPC, create one
route table `net-lab-dx-main`, associate + propagate the VPC attachment, add
`192.168.30.0/16 → TGW` to the aws VPC's route table. Same steps as Lab 2 step 4.

## 5. ⭐ NEW — DX Gateway (the as-code control plane)
**Direct Connect console → Direct Connect gateways → Create Direct Connect gateway**:
- Name: `net-lab-dx`
- Amazon side ASN: pick one not already used by another gateway in the account (e.g. `64513`)

**Associate it with the TGW:** on the new gateway → **Transit Gateway associations → Associate
Transit Gateway**:
- Transit Gateway: `net-lab-dx`
- **Allowed prefixes: `192.168.30.0/16`** — the on-prem CIDR this association is allowed to
  advertise from the TGW side out toward on-prem. (On a live DX this is also what a real Transit
  VIF would carry in over BGP; here it documents the intended reachable range since no physical
  VIF exists.) This creates an implicit TGW attachment of type `direct-connect-gateway` — no
  separate "attachment" step needed.

**🖐️ The one manual/physical step that stops here:** a real deployment now needs a **connection**
(or hosted connection) requested from a DX partner at a DX location, then a **Transit VIF**
created on it (BGP session straight to this DX Gateway). That's a procurement + physical
cross-connect process, documented as the next step, not something to click through in a lab.

## 6. VPN as the transport stand-in — same pattern as Lab 2
Elastic IP → Customer Gateway (BGP ASN `65000`, IP = the EIP) → Site-to-Site VPN connection
(target = TGW `net-lab-dx`, dynamic/BGP routing) → associate + propagate its TGW attachment into
`net-lab-dx-main`. Identical to Lab 2 step 5, just pointed at this lab's TGW.

## 7. strongSwan box + software config — identical to Lab 2 steps 6–7
Same instance setup (disable source/dest check, associate the EIP, on-prem route to its ENI) and
the same strongSwan + FRR config (BGP ASN `65000` ↔ `64512`, advertising `192.168.30.0/16`) —
copy Lab 2's step 6–7 exactly, just in this lab's VPCs/TGW.

## 8–9. Test EC2 + verify — identical to Lab 2 steps 8–9
Same SSM + `t4g.micro` test hosts, same ping-across-the-tunnel verification.

## Stretch
- **VIF types:** in the Direct Connect console (no physical connection needed to read this),
  compare what a **Private VIF** (→ a VGW, single VPC) vs this lab's **Transit VIF** (→ a DX
  Gateway → TGW, multi-VPC/multi-region) vs a **Public VIF** (→ S3/DynamoDB over DX, not through
  the internet) each attach to.
- **Encryption:** DX itself is **not encrypted** by default — note where **MACsec** (on supported
  ports) or a **VPN-over-DX** overlay would go if this were a real line.
- **Resilience:** read AWS's documented "Maximum Resiliency" model (2 connections at 2 separate DX
  locations) and where a VPN would sit as backup (lower BGP local-pref than the DX path).

## Clean up
Same order as Lab 2, plus: DX Gateway TGW association → DX Gateway, before the TGW itself.
