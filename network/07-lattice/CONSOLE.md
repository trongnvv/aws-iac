# Lab 7 — VPC Lattice: console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. VPC A = client, VPC B = service
— again **identical CIDR `10.0.0.0/16` on purpose**: Lattice is L7 (HTTP), there's no L3 routing
involved at all, so overlap is a non-issue. There's also deliberately **no peering/TGW between A
and B** — the service network is the only thing that connects them.

## 1. Two VPCs, same CIDR
**VPC console → Your VPCs → Create VPC**:

| Name | CIDR |
|---|---|
| `net-lab-lattice-a` (client) | `10.0.0.0/16` |
| `net-lab-lattice-b` (service) | `10.0.0.0/16` |

Both need **DNS resolution enabled** (it's on by default for a new VPC) — clients resolve the
Lattice service's DNS name through the VPC resolver, which Lattice hijacks for its link-local
`169.254.171.x` data path once the VPC is associated to a service network.

## 2. One subnet + IGW + route table per VPC
Same pattern as before: `10.0.0.0/24`, auto-assign public IP, IGW, route table `0.0.0.0/0 → IGW`
for SSM only. No route between A and B.

## 3. Security groups — the classic Lattice gotcha
Lattice sends health checks and data traffic to the target from its own **managed prefix list**,
**not** from the VPC/client CIDR. Miss this and your target shows UNHEALTHY with no obvious reason.

**VPC console → Security groups → Create security group**, one per VPC:
- Inbound: **TCP 80**, source = **a prefix list** → pick `com.amazonaws.ap-southeast-1.vpc-lattice`
  (search "lattice" in the source field's prefix-list option)
- Inbound (convenience): also allow TCP 80 from `10.0.0.0/16` for same-VPC curl/testing
- Egress: all

## 4. Service network — the mesh backplane
**VPC Lattice console → Service networks → Create service network**:
- Name: `net-lab-lattice`
- Auth type: **AWS IAM**

### Network-level auth policy
**Service network → Access → Edit** (or the auth policy tab), paste an allow-all policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": "*", "Action": "vpc-lattice-svcs:Invoke", "Resource": "*"}]
}
```
(This only takes effect because the network's auth type is AWS_IAM — a `NONE` auth type ignores
policies entirely.)

### Associate both VPCs
**Service network → VPC associations → Associate VPC**, once for A and once for B — pick the
matching security group from step 3 for each. This is what actually injects the Lattice resolver
+ data path into each VPC; nothing works before this.

## 5. The target service (VPC B)
**EC2 console → Launch instance**: VPC B's subnet, `t4g.micro`, Amazon Linux 2023 arm64, the SSM
role (same `net-lab-ssm` as other labs), SG from step 3 (VPC B's), no key pair. Name:
`net-lab-lattice-service-b`.

**Session Manager in**, serve test pages:
```bash
sudo mkdir -p /srv/www/v1 /srv/www/v2
echo "hello from service B - default" | sudo tee /srv/www/index.html
echo "service B /v1 response" | sudo tee /srv/www/v1/index.html
echo "service B /v2 response" | sudo tee /srv/www/v2/index.html
cd /srv/www && sudo nohup python3 -m http.server 80 >/var/log/httpd.log 2>&1 &
```

## 6. Target group
**VPC Lattice console → Target groups → Create target group**:
- Type: **Instances**
- Protocol: HTTP, port 80, VPC: `net-lab-lattice-b`
- Health check: HTTP, path `/`, port 80, matcher `200`
- Register target: the EC2 instance from step 5, port 80

## 7. The Lattice service
**VPC Lattice console → Services → Create service**:
- Name: `net-lab-lattice-svc-b`
- Auth type: **AWS IAM**

### Per-service auth policy
Same allow-all JSON as step 4's network policy, attached on the **service's** auth policy tab.
(Stretch: tighten this one specifically for the 403 test — see below.)

### Listener
**Service → Listeners → Add listener**: HTTP, port 80, default action **forward** 100% to the
target group from step 6.

### Attach to the network
**Service → Service network associations → Associate** → pick `net-lab-lattice`. This is the step
that actually publishes the service to every VPC associated with that network — without it the
service exists but nothing can reach it.

Copy the service's generated DNS name from **Service → Overview**
(`<name>-<suffix>.<id>.vpc-lattice-svcs.ap-southeast-1.on.aws`).

## 8. Client test host (VPC A)
**EC2 console → Launch instance**: VPC A's subnet, `t4g.micro`, same SSM role, VPC A's SG, no key
pair.

## 9. Verify
**Session Manager into the VPC A client:**
```bash
curl http://<service DNS name>/
```
You should get "hello from service B - default" — reached across two VPCs with **overlapping
CIDR** and **no peering/TGW at all**, purely through the Lattice service network.

## Stretch
- **Path/header routing:** add a second target group (or reuse one with different content), then
  **Service → Listeners → [listener] → Add rule**: match path `/v1` → forward to one TG, `/v2` →
  another. `curl http://<dns>/v1` and `/v2` should return the distinct bodies seeded in step 5.
- **Auth policy (IAM):** edit the per-service auth policy to a specific principal (not `"*"`) —
  calling from an unauthorized caller (e.g. a different IAM role with no matching policy) should
  now get a **403**, proving IAM-based zero-trust service-to-service auth.
- **vs PrivateLink/TGW:** note the trade in your own words after doing all three labs — Lattice is
  managed L7 mesh-lite (per-request + data cost, newest); PrivateLink is L4 one-service expose;
  TGW is L3 bulk routing.

## Clean up
Service (detach from network first) → target group → service network VPC associations → service
network → EC2 instances → IGWs → subnets → VPCs → the `net-lab-ssm` IAM role.
