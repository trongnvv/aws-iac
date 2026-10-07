# Lab 2 — Site-to-Site VPN → Transit Gateway (hybrid over IPsec + BGP)

Test plan: `../README.md` (lab 2). Concept: workbook `01_Knowledge/Network/Cloud-Connectivity/`.

Connects a **simulated on-prem data center** to an AWS VPC over an **IPsec Site-to-Site VPN** that
terminates on a **Transit Gateway**, with **BGP** exchanging routes (2 tunnels for HA). The on-prem
side is a VPC (`192.168.0.0/16`) whose **strongSwan + FRR** EC2 plays the Customer Gateway. Once the
tunnels are UP and BGP is established you can SSM into either side and ping across — self-contained,
independent of lab 1 (its own TGW + VPCs).

## Architecture
```mermaid
graph LR
  subgraph onprem["'On-prem' VPC 192.168.0.0/16"]
    oh["test host<br/>192.168.0.x"]
    cgw["strongSwan + FRR EC2<br/>Customer GW · EIP · BGP ASN 65000"]
    oh --- cgw
  end
  subgraph aws["AWS — VPC 10.10.0.0/16"]
    ah["test host<br/>10.10.0.x"]
    TGW{{"Transit Gateway<br/>amazon-side ASN 64512"}}
    ah --- TGW
  end
  cgw ==>|"Tunnel 1 — IPsec (IKEv2) + BGP"| TGW
  cgw ==>|"Tunnel 2 — IPsec + BGP (HA / ECMP)"| TGW
  TGW -. "advertises 10.10/16 &rarr; on-prem" .-> cgw
  cgw -. "advertises 192.168/16 &rarr; AWS (BGP)" .-> TGW
```

## Structure (layered — each folder is its own state, like the eks env layers)
| Layer | Builds | Depends on |
|---|---|---|
| `1-vpc/` | 2 VPCs (`aws` 10.10/16 + `onprem` 192.168/16) + public subnet + IGW + RT + SGs (ICMP both sides; a strongSwan SG opening IKE/NAT-T/ESP) | — |
| `2-tgw/` | Transit Gateway (amazon ASN 64512, ECMP on) + aws VPC attachment + 1 route table + route `aws → 192.168/16 → TGW` | 1-vpc |
| `3-vpn/` | EIP for the appliance + `aws_customer_gateway` (BGP ASN 65000) + `aws_vpn_connection` to the TGW (2 tunnels, dynamic/BGP) + TGW RT assoc/propagation for the VPN attachment | 1-vpc, 2-tgw |
| `4-strongswan/` | the on-prem CGW appliance (`t4g.micro` AL2023, `source_dest_check=false`) running **strongSwan** (2 IPsec tunnels via VTI + fwmark) + **FRR** (BGP) from templated user_data; SSM IAM role/profile (`net-lab-vpn-ssm`); EIP assoc; route `onprem → 10.10/16 → strongSwan ENI` | 1-vpc, 3-vpn |
| `5-ec2/` | 2 test hosts (`t4g.micro`, AL2023, SSM, no SSH) — one in each VPC | 1-vpc, 4-strongswan |

> The IPsec/BGP config in `4-strongswan/user_data.sh.tftpl` is templated from the `aws_vpn_connection`
> attributes (tunnel outside/inside addresses, PSKs, both BGP ASNs). It was **built blind** — see the
> **⚠️ Verify live** section before trusting it end-to-end.

## Run
Prereq (once per account): create the state bucket via foundation — `(cd ../../foundation/00-tf-backend && tofu init && tofu apply)`
provisions **`network-iac-tfstate`**. State lives there, one key per layer (`02-vpn/<layer>/…`).
```bash
cd ~/src/github/trongnvv/aws-iac/network/02-vpn
./deploy.sh                       # applies 1-vpc → 2-tgw → 3-vpn → 4-strongswan → 5-ec2, prints IPs
# or per layer:  (cd 1-vpc && tofu init && tofu apply)  … then 2-tgw, 3-vpn, 4-strongswan, 5-ec2
```

## Test checklist (pass/fail)
Run top to bottom. Each check = one step + its PASS/FAIL. Tick the box when PASS. A FAIL points to the
Troubleshooting row below. Tunnels take ~1–2 min to come UP and BGP ~30s more to establish. First grab
the IDs + private IPs and the VPN id:
```bash
cd 5-ec2 && tofu output instances       # {aws,onprem} → {id, private_ip}
# export for the commands below (fill from the output):
AWS_ID=i-aws…    ; ON_ID=i-onprem…
AWS_IP=10.10.0.x ; ON_IP=192.168.0.x
# the strongSwan appliance + the VPN connection:
SS_ID=$(cd 4-strongswan && tofu output -raw strongswan_instance_id)
VPN_ID=$(cd 3-vpn && tofu output -raw vpn_connection_id)
TGW_RT=$(cd 2-tgw && tofu output -raw tgw_route_table_id)
```

- [ ] **T0 — all 3 hosts registered in SSM** (aws test host + onprem test host + strongSwan; wait ~1–2 min after apply)
  ```bash
  aws ssm describe-instance-information \
    --query "InstanceInformationList[].{id:InstanceId,ping:PingStatus}" --output table
  ```
  **PASS:** all 3 instances present, `PingStatus = Online`. **FAIL:** fewer than 3 / not Online → TS "SSM not registering".

- [ ] **T1 — VPN tunnels UP** (at least 1, ideally both)
  ```bash
  aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
    --query 'VpnConnections[].VgwTelemetry[].{outside:OutsideIpAddress,status:Status,routes:AcceptedRouteCount}' \
    --output table
  # want: Status=UP, AcceptedRouteCount >= 1 (BGP learned 192.168/16)
  ```
  **PASS:** ≥1 tunnel `Status=UP` (ideally both), `AcceptedRouteCount >= 1`. **FAIL:** all DOWN → TS "Tunnel DOWN".

- [ ] **T2 — BGP established on the strongSwan appliance** *(needs the built-blind appliance config — see ⚠️ Verify live)*
  ```bash
  aws ssm start-session --target "$SS_ID"
    sudo swanctl --list-sas                  # both children INSTALLED (IPsec up first)
    sudo vtysh -c 'show bgp summary'         # each neighbor State/PfxRcd = a number (Established), not Active/Connect
    sudo vtysh -c 'show ip route bgp'        # learned 10.10.0.0/16 via the vgw inside addrs
    exit
  ```
  **PASS:** neighbors show a numeric `PfxRcd` (Established) and received prefixes `> 0` (10.10/16 learned). **FAIL:** neighbor stuck `Active`/`Connect`, PfxRcd=0 → TS "BGP not established".

- [ ] **T3 — aws → on-prem reachable** (cloud → on-prem over the VPN)
  ```bash
  aws ssm start-session --target "$AWS_ID"
    ping -c3 $ON_IP        # expect replies from 192.168.0.x
    exit
  ```
  **PASS:** `0% packet loss`. **FAIL:** timeout → if the reverse (T4) works it's one-way → TS "ping one-way"; if both fail → TS "ping fails (tunnels+BGP UP)".

- [ ] **T4 — on-prem → aws reachable** (on-prem → cloud via strongSwan ENI → tunnel)
  ```bash
  aws ssm start-session --target "$ON_ID"
    ping -c3 $AWS_IP       # expect replies from 10.10.0.x
    exit
  ```
  **PASS:** `0% packet loss`. **FAIL:** timeout → if T3 works it's one-way → TS "ping one-way"; else → TS "ping fails (tunnels+BGP UP)".

- [ ] **T5 — on-prem CIDR learned via BGP on the TGW** (route propagated, not static)
  ```bash
  aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$TGW_RT" \
    --filters Name=state,Values=active \
    --query 'Routes[].{cidr:DestinationCidrBlock,type:Type,state:State}' --output table
  # want: 192.168.0.0/16 present, Type=propagated (from the VPN attachment via BGP)
  ```
  **PASS:** `192.168.0.0/16` present with `Type=propagated`. **FAIL:** missing / only static → TS "on-prem CIDR not propagated".

**Result:** all boxes ticked = lab passes (IPsec tunnels UP, BGP established, bidirectional reachability on-prem ↔ cloud, on-prem route learned over BGP).

## Troubleshooting — debug flow
When a check fails, don't guess: **walk the data path layer by layer** — and for the pure-IP hops (SG →
route → TGW propagation) **let VPC Reachability Analyzer pinpoint the blocking hop** first. The IPsec/BGP
layer (T1/T2) is below the analyzer's view, so those flows SSM into the appliance instead. General method:
vault `01_Knowledge/Network/Cloud-Connectivity/Debug-Strategy.md`.

First grab the ids the flows reuse (instance ids come straight from the `5-ec2` output):
```bash
eval "$(cd 5-ec2 && tofu output -json instances | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k,p in {"aws":"AWS","onprem":"ON"}.items():
    v=d[k]; print(p+"_ID="+v["id"]+"; "+p+"_IP="+v["private_ip"])
')"
SS_ID=$(cd 4-strongswan && tofu output -raw strongswan_instance_id)
SS_EIP=$(cd 3-vpn && tofu output -raw strongswan_eip)
VPN_ID=$(cd 3-vpn && tofu output -raw vpn_connection_id)
TGW_RT=$(cd 2-tgw && tofu output -raw tgw_route_table_id)
echo "aws=$AWS_ID/$AWS_IP  onprem=$ON_ID/$ON_IP  strongswan=$SS_ID eip=$SS_EIP"   # sanity-check
```

### Step 0 — ask the analyzer which hop blocks (no SSH/ping needed)
Reachability Analyzer models the **VPC/TGW/SG/route** path end-to-end, so use it for the IP-forwarding
failures (T3/T4). It does **not** see inside the IPsec tunnel — if it reports `Reachable=True` yet ping
still fails, the break is the tunnel/BGP layer → go to Flow A/B instead.
```bash
analyze() {  # analyze <src-instance-id> <dst-instance-id>  → prints Reachable + the blocking component
  pid=$(aws ec2 create-network-insights-path --source "$1" --destination "$2" --protocol icmp \
        --query NetworkInsightsPath.NetworkInsightsPathId --output text)
  aid=$(aws ec2 start-network-insights-analysis --network-insights-path-id "$pid" \
        --query NetworkInsightsAnalysis.NetworkInsightsAnalysisId --output text)
  aws ec2 wait network-insights-analysis-available --network-insights-analysis-ids "$aid" 2>/dev/null
  aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$aid" \
    --query 'NetworkInsightsAnalyses[0].{Reachable:NetworkPathFound,Blocked:Explanations[0].ExplanationCode}' --output table
  aws ec2 delete-network-insights-path --network-insights-path-id "$pid" >/dev/null 2>&1   # cleanup ($0.10/analysis)
}
analyze "$AWS_ID" "$ON_ID"   # aws → on-prem;  swap args for the reverse
```
`Reachable=True/False` is the verdict; `Blocked` names the hop (`ENI_SG_RULES_MISMATCH`,
`NO_ROUTE_TO_DESTINATION`, `TGW_ROUTE_TABLE_...`, …). Then go to the matching flow:

### Flow A — tunnel DOWN (T1): `VgwTelemetry Status=DOWN`
IPsec never came up, so BGP and ping can't either. Confirm then walk the IKE/ESP path:
```bash
aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
  --query 'VpnConnections[].VgwTelemetry[].{Status:Status,LastChange:LastStatusChange,Msg:StatusMessage}' \
  --output table
```
1. **Appliance IPsec state** — SSM in and check the SAs: `aws ssm start-session --target "$SS_ID"` → `sudo swanctl --list-sas`. Both children should be `INSTALLED`. Nothing listed / `CONNECTING` → IKE isn't completing. `sudo journalctl -u strongswan -n50` shows *why* (proposal mismatch, auth failure).
2. **Customer gateway IP == appliance EIP** — the CGW in `3-vpn` dials back to the EIP; if the EIP isn't associated the two-way IKE never forms. `aws ec2 describe-customer-gateways --query 'CustomerGateways[].IpAddress'` must equal `$SS_EIP`. Mismatch → EIP not associated (`4-strongswan` `aws_eip_association`).
3. **PSK match** — `sudo swanctl --list-conns` on the appliance, compare the secret against `(cd 3-vpn && tofu output tunnel1_psk)` / `tunnel2_psk`. Auth-failure in the log = PSK or `id-aws` (keyed by tunnel outside IP) mismatch. Fix: how `4-strongswan/user_data.sh.tftpl` writes `ipsec.secrets`.
4. **SG lets IKE/ESP in** — the appliance SG must allow **UDP 500 + UDP 4500 + protocol 50 (ESP)** from AWS's two tunnel outside IPs. Fix in `1-vpc/security.tf` `aws_security_group.strongswan` (lab opens these to `0.0.0.0/0`). `tunnel1_address`/`tunnel2_address` outputs in `3-vpn` are those AWS endpoints.

### Flow B — BGP not established (T2): neighbor stuck `Active`/`Connect`, `PfxRcd=0`
IPsec is UP (Flow A passes) but BGP rides inside the tunnel and isn't peering. **This is the built-blind
appliance config (`4-strongswan/user_data.sh.tftpl` — FRR) — the most likely thing to need live tuning;
flag it.** SSM into the appliance:
```bash
aws ssm start-session --target "$SS_ID"
  sudo swanctl --list-sas                 # children INSTALLED? (BGP needs IPsec up first)
  ip addr show type vti                   # each VTI has its cgw inside /30? (169.254.x.x)
  sudo vtysh -c 'show bgp summary'        # neighbor State = Established, not Active/Connect
  sudo vtysh -c 'show ip route bgp'       # 10.10.0.0/16 learned via the vgw inside addrs?
  exit
```
Walk it: 1) **VTIs up with the inside /30** — missing → the `ip link add … type vti key N` + fwmark pairing failed (the crux hop). 2) **neighbor = the vgw inside address** of each tunnel (`tunnel1_vgw_inside`/`tunnel2_vgw_inside` from `3-vpn`), **not** the cgw side. 3) **ASN pairing** — FRR must peer as on-prem **65000** (`onprem_bgp_asn`) to amazon **64512** (`amazon_side_asn`); a swapped/wrong remote-as leaves it `Active`. 4) **`no bgp ebgp-requires-policy`** present — FRR 9 filters all routes without it. All in the FRR block of `4-strongswan/user_data.sh.tftpl`.

### Flow C — ping fails one or both ways (T3/T4), tunnels+BGP UP
Run `analyze "$AWS_ID" "$ON_ID"` (and the reverse) from Step 0 to find the blamed hop, then confirm that
hop. If the analyzer says `Reachable=True` but ping still times out → the break is **inside the tunnel**
(Flow A/B) or **appliance forwarding** (step 5 below), which the analyzer can't see. Walk the path:
1. **SG** — `aws ec2 describe-security-groups --group-ids <sg> --query 'SecurityGroups[0].IpPermissions'` must allow ICMP from **both** `10.0.0.0/8` **and** `192.168.0.0/16`. Fix in `1-vpc/security.tf` (`aws_security_group.this` + `.strongswan`). (`ENI_SG_RULES_MISMATCH` points here.)
2. **VPC route out** — aws RT needs `192.168.0.0/16 → tgw-…`; onprem RT needs `10.10.0.0/16 → the strongSwan ENI`. `aws ec2 describe-route-tables --route-table-ids <rt> --query 'RouteTables[0].Routes'`. Missing → `2-tgw` (aws side) or `4-strongswan` (onprem → ENI route). (`NO_ROUTE_TO_DESTINATION`.)
3. **TGW route table / VPN attachment propagation** — see Flow D; a missing `192.168/16` propagation blocks aws→onprem at the TGW (`TGW_ROUTE_TABLE_...`).
4. **Return route** — a one-way result = the reverse path is broken. aws→onprem OK but onprem→aws fails: onprem RT lacks `10.10/16 → ENI`, or aws SG blocks ICMP from `192.168/16`, or the aws attachment isn't propagated. Reverse case: aws RT lacks `192.168/16 → TGW`, or onprem SG blocks `10/8`, or the VPN attachment's `192.168/16` isn't propagated (T5/Flow D).
5. **Appliance forwarding** (analyzer-blind) — both ways fail with `Reachable=True`: on the appliance `source_dest_check=false` (`4-strongswan` `aws_instance.strongswan`) **and** `sudo sysctl net.ipv4.ip_forward` = 1.

### Flow D — on-prem CIDR not propagated (T5): `192.168/16` missing from the TGW RT
```bash
aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$TGW_RT" \
  --filters Name=state,Values=active \
  --query 'Routes[].{cidr:DestinationCidrBlock,type:Type,state:State}' --output table
```
Expect `192.168.0.0/16` present with `Type=propagated` (learned over BGP from the VPN attachment).
Missing → 1) **BGP must be Established first** (T2/Flow B) — the route is learned, not static; fix BGP
first. 2) **VPN attachment associated + propagated** to this RT (`3-vpn`
`aws_ec2_transit_gateway_route_table_association.vpn` + `...propagation.vpn`). 3) FRR actually advertises
`192.168.0.0/16` out (`network 192.168.0.0/16` in the FRR config, `4-strongswan/user_data.sh.tftpl`).
4) the `aws_vpn_connection` is **dynamic** (`static_routes_only = false`, `3-vpn/vpn.tf`), not static.

### Flow E — ping works small, fails/stalls on large payloads (MSS/MTU)
Not a reachability break — PMTUD. VPN path ≈ 1500 but IPsec overhead cuts the effective MSS to ~1379.
VTI MTU is set to 1419 in user_data; add **MSS clamping** (`iptables -t mangle -A FORWARD -p tcp
--tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu` in `4-strongswan/user_data.sh.tftpl`) and re-test
with `ping -M do -s <size>` on a live tunnel.

### Quick table (symptom → first move)
| Symptom | First move |
|---|---|
| `start-session` fails / not in SSM | wait ~1–2 min; `aws ssm describe-instance-information` → all 3 `PingStatus=Online`? Else check IGW route (`1-vpc`) + the `AmazonSSMManagedInstanceCore` profile (`net-lab-vpn-ssm`, `4-strongswan`). Plugin missing → `brew install --cask session-manager-plugin`. |
| tunnel `Status=DOWN` (T1) | Flow A (appliance IPsec → CGW IP == EIP → PSK → SG UDP 500/4500 + ESP) |
| BGP neighbor `Active`/`Connect`, `PfxRcd=0` (T2) | Flow B (VTI /30 → vgw inside peer → ASN 65000↔64512 → `ebgp-requires-policy`) — built-blind FRR config |
| ping times out, tunnels+BGP UP (T3/T4) | Flow C (analyzer → SG → VPC route → TGW propagation → return route → appliance forwarding) |
| ping one-way only | Flow C step 4 (the reverse path: return route / return SG / reverse propagation) |
| `192.168/16` not in TGW RT (T5) | Flow D (BGP up first → VPN attachment propagation → FRR advertises → dynamic VPN) |
| large pings stall, small OK | Flow E (MSS/MTU clamping) |
| `3-vpn`/`4-strongswan` apply: remote state empty | run the earlier layer first (`./deploy.sh` does the order). |

## Test EC2 recipe (reused by every lab)
Small, cheap, no SSH: `t4g.micro` + Amazon Linux 2023 (arm64) + `AmazonSSMManagedInstanceCore` role
(here `net-lab-vpn-ssm`, created in `4-strongswan`) in a **public** subnet (public IP + IGW) so the
SSM agent reaches AWS without a NAT/endpoints. Reach it with `aws ssm start-session`. Cross-site
traffic goes **private** over the VPN/TGW; the public IP is management-only. See `4-strongswan/` +
`5-ec2/`. The strongSwan appliance uses the same base image + profile, plus `source_dest_check=false`
and strongSwan/FRR from the AL2023 repos.

## Teardown
```bash
./teardown.sh                     # destroys 5-ec2 → 4-strongswan → 3-vpn → 2-tgw → 1-vpc
# cost-save mid-lab: (cd 5-ec2 && tofu destroy) + (cd 4-strongswan && tofu destroy)
#   drops the EC2s; the VPN connection itself still bills until 3-vpn is destroyed.
```

## Cost (while running)
VPN connection ≈ **$0.05/hour** + TGW attachments ≈ $0.05/attachment-hour × 2 (aws VPC + VPN) + data ·
2× `t4g.micro` test + 1× strongSwan ≈ $0.025/h × 3 · EIP (strongSwan) + 3× public IPv4 ≈ $0.005/h × 4 →
**~$0.25/hour**. Billed hourly even idle → **destroy when done**.

## ⚠️ Verify live (built blind)
This lab's AWS resource wiring (VPC/TGW/CGW/VPN/routes/EC2) is standard and `tofu validate`-clean, but
the **appliance config is best-effort and WILL likely need live tuning**. The VPN won't come up purely
from `tofu apply` until these are confirmed on a real deploy:

- **strongSwan swanctl.conf** — AL2023 ships strongSwan 5.9 with the swanctl/vici backend (not legacy
  `ipsec.conf`). Verify the service unit name (`strongswan` vs `strongswan-swanctl`), that
  `swanctl --load-all` actually loads both connections, and that the **PSK `id-aws`** matching (keyed
  by the tunnel outside IP) is accepted by AWS. Proposals (`aes128-sha1-modp1024`) match AWS defaults
  but AWS now offers stronger — confirm the negotiated proposal in `swanctl --list-sas`.
- **Route-based VTI + fwmark** — the `ip link add … type vti key N` + `mark_in/mark_out=N` pairing is
  the crux. If encrypted traffic doesn't flow, check `ip -s xfrm state`, the fwmark on the VTI, and
  `disable_policy`. This is the single most likely thing to need hand-tuning.
- **BGP established** — FRR 9 syntax (`no bgp ebgp-requires-policy`, `timers 10 30`); confirm neighbors
  reach **Established** and that `192.168/16` is advertised out and `10.10/16` learned in.
- **ping both ways** — the end-to-end proof; depends on forwarding + `source_dest_check=false` + the
  two VPC routes + TGW propagation all being correct together.
- **MSS/MTU & PMTUD** — VTI MTU is pre-set to 1419 and MSS clamping is noted but **not applied** in
  user_data; apply + measure with `ping -M do -s <size>` on a live tunnel.

### Stretch (from the plan — do after Core passes live)
- [ ] **BGP failover/convergence:** drop tunnel 1 (`sudo swanctl --terminate --child aws-tunnel1`) →
      measure time for traffic to fail over to tunnel 2 (BGP timers `10 30` + DPD `10s` set to keep it fast).
- [ ] **ECMP:** TGW has `vpn_ecmp_support=enable`; on FRR drop the `T2-BACKUP` local-pref route-map and
      add `maximum-paths 2` so both tunnels load-balance → confirm flows spread across tunnel1+tunnel2.
- [ ] **MTU / PMTUD:** find the working MSS with the DF bit, add MSS clamping, confirm no fragmentation
      (VPN path ≈ 1500 → effective MSS ≈ 1379).
