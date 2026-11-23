# Lab 3 — PrivateLink: console walkthrough

Same lab as the Terraform here, by hand. Region `ap-southeast-1`. VPC A = provider (exposes a
service), VPC B = consumer. **Both VPCs use the identical CIDR `10.0.0.0/16` on purpose** — the
whole point of PrivateLink is that it doesn't route between VPC CIDRs at all, so an overlap is a
non-issue.

## 1. Two VPCs, same CIDR
**VPC console → Your VPCs → Create VPC** (VPC only):

| Name | CIDR |
|---|---|
| `net-lab-pl-a` (provider) | `10.0.0.0/16` |
| `net-lab-pl-b` (consumer) | `10.0.0.0/16` |

## 2. One subnet + IGW + route table per VPC
Same pattern as Lab 1/5: `10.0.0.0/24` subnet (auto-assign public IPv4 on), IGW attached,
route table with `0.0.0.0/0 → IGW`. **There is no route between A and B** — don't add one;
PrivateLink needs none.

## 3. Security groups
**VPC console → Security groups → Create security group**:
- `net-lab-pl-provider-svc` (in VPC A) — inbound **TCP 80** from `10.0.0.0/16` (the NLB health
  check + traffic looks like it's from inside the VPC), egress all.
- `net-lab-pl-consumer-host` (in VPC B) — egress all only, no inbound needed.
- `net-lab-pl-endpoint` (in VPC B, for the endpoint ENI — create this in step 6) — inbound
  **TCP 80 and 443** from `10.0.0.0/16`, egress all.

## 4. The service (VPC A)
**EC2 console → Launch instance**, in VPC A's subnet, `t4g.micro`, Amazon Linux 2023 arm64, SG
`net-lab-pl-provider-svc`, IAM instance profile = an SSM role (same `net-lab-ssm` pattern as
Lab 1 — create it first if you haven't: IAM → Roles → trust EC2 → attach
**AmazonSSMManagedInstanceCore**), no key pair. Name: `net-lab-pl-service`.

Once it's running, **Connect via Session Manager** and serve a test page:
```bash
sudo mkdir -p /opt/www
echo "hello from PrivateLink provider (VPC A)" | sudo tee /opt/www/index.html
sudo tee /etc/systemd/system/labhttp.service <<'UNIT'
[Unit]
Description=Lab HTTP service
After=network.target
[Service]
WorkingDirectory=/opt/www
ExecStart=/usr/bin/python3 -m http.server 80
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now labhttp
```

## 5. Internal NLB in front of it
**EC2 console → Load Balancers → Create load balancer → Network Load Balancer**:
- Scheme: **Internal**
- Name: `net-lab-pl-nlb`, VPC A, the one subnet
- Listener: **TCP 80**
- Target group: **Create new** — `net-lab-pl-tg`, target type **Instances**, protocol TCP port 80,
  health check TCP:80 — register the service instance from step 4.

## 6. Publish it as an Endpoint Service
**VPC console → Endpoint services → Create endpoint service**:
- Load balancer type: **Network**, select `net-lab-pl-nlb`
- **Require acceptance: No** (off) — so the consumer can connect without a manual approval step
  (fine for a lab; a real service with unknown consumers would turn this on)

Copy the generated **service name** (`com.amazonaws.vpce.ap-southeast-1.vpce-svc-xxxxxxxx`) — the
consumer needs it next.

## 7. The interface endpoint (VPC B)
**VPC console → Endpoints → Create endpoint**:
- Service category: **Other endpoint services**
- Service name: paste the `vpce-svc-...` name from step 6 → **Verify service**
- VPC: `net-lab-pl-b`, the one subnet
- Security group: `net-lab-pl-endpoint`
- **Private DNS names: leave unchecked** — a custom endpoint service doesn't have verified private
  DNS by default (that's the stretch goal below), so the consumer uses the endpoint's own
  AWS-generated DNS name instead.

This drops an ENI into B's subnet with a private IP **from B's own CIDR**. That ENI is what the
consumer actually talks to — no CIDR from A is ever involved, which is why the overlap doesn't matter.

## 8. Test host (VPC B)
**EC2 console → Launch instance**, VPC B's subnet, `t4g.micro`, same SSM role, SG
`net-lab-pl-consumer-host`, no key pair.

## 9. Verify
**Session Manager into the VPC B test host:**
```bash
curl http://<endpoint's DNS name>   # from Endpoints → [endpoint] → DNS names tab
```
You should see "hello from PrivateLink provider (VPC A)" — reached entirely through the endpoint
ENI, never routed between the two overlapping `10.0.0.0/16` blocks.

## Stretch
- **Private DNS name:** on the endpoint, enable **private DNS names** (the endpoint service owner
  must also verify a domain first, or you can skip verification for a lab and just observe the
  option) — once on, the service's own domain name resolves to the endpoint's private IP
  transparently, no need to know the generated `vpce-...` name.
- **Cross-zone LB:** on the NLB, toggle **cross-zone load balancing** and add a target in a second
  AZ — note the cross-AZ data transfer charge this introduces.

## Clean up
Interface endpoint (VPC B) → endpoint service (VPC A) → NLB + target group → EC2 instances →
IGWs → subnets → VPCs → the `net-lab-ssm` IAM role.
