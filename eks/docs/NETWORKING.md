# Networking — north-south, egress, intra-VPC

Design decisions and options for traffic **in, out, and across** the cluster. For the
packet-level mechanics (route tables, VPC CNI IP allocation, cross-account ENIs) see
[`MODULES.md`](MODULES.md) `modules/network`. This file = *what to choose and when*.

```
        Internet
           │  ▲
   inbound │  │ outbound (egress)
           ▼  │
   ┌──────────────────────────┐
   │ ALB / NLB (public subnet) │  ← §1
   └──────────────────────────┘
           │  ▲
           ▼  │
   ┌──────────────────────────┐        ┌───────────────────┐
   │ pods (private-app subnet) │──§3──▶│ RDS / cache (iso) │
   └──────────────────────────┘        └───────────────────┘
           │  ▲
           ▼  │ §2
   NAT (static EIP) / Network Firewall → partner / exchange
```

---

## 1. Inbound (north-south in)

```
Internet → [CloudFront → WAF/Shield] → [ALB/NLB (LBC)] → [API GW (Kong)] → Service
```

The **AWS Load Balancer Controller** (`envs/<env>/01-addons/02-aws-load-balancer-controller`) provisions **both** load
balancer types from Kubernetes objects — choose per workload:

| | **ALB** (L7) | **NLB** (L4) |
|---|---|---|
| Created from | `Ingress` | `Service type=LoadBalancer` (`aws-load-balancer-type: external`) |
| Protocols | HTTP / HTTPS / gRPC | TCP / UDP / TLS (anything) |
| Routing | host / path / header | port only |
| Client source IP | via `X-Forwarded-For` | **preserved** (real IP) |
| Static IP | no (DNS name) | **yes — EIP per AZ** (partner allowlisting) |
| WAF attach | ✅ | ❌ (WAF is L7 only) |
| TLS | terminate (ACM) | terminate **or passthrough** |
| Latency / throughput | higher | **lowest / very high** |
| Use for | web, REST, normal ingress | non-HTTP, gRPC, low-latency, source/static-IP needs |

Both use **target-type `ip`** — traffic lands directly on the pod IP (VPC CNI real IPs),
skipping the node-port hop.

> **Finance/exchange workloads** (FIX, market-data feeds): **NLB** is usually the edge —
> low latency, static EIP for exchange allowlisting, and preserved source IP.

### Two ingress models — and the hybrid we run

On EKS the "ingress controller" role can be filled two ways:

**A · AWS LBC + ALB** — the controller is *control-plane only*: it watches `Ingress`
(class `alb`) and programs a real, AWS-managed ALB. Traffic goes **straight to pod IPs**,
the controller is **not** in the data path.
```
Internet → ALB (AWS-managed, public subnet) → pod IP        [2 hops]
              ▲ LBC programs it (control-plane)
```

**B · In-cluster proxy (Kong / ingress-nginx)** — the controller **is** the data-plane:
a proxy pod terminates + routes. It sits behind one LB shared by many routes.
```
Internet → NLB/ALB ×1 → proxy pod (Kong/nginx) → ClusterIP → pod   [3 hops]
                           ▲ controller = the proxy itself
```

| | A · LBC + ALB | B · in-cluster proxy |
|---|---|---|
| Controller | control-plane (programs ALB) | data-plane (proxy pods) |
| LB count | 1 ALB per `Ingress` (`group.name` to share) | 1 LB → many routes |
| TLS / WAF | ACM + AWS WAF on the ALB | in-cluster cert + own WAF |
| L7 features | host/path only | auth, rate-limit, transform, plugins |
| Scaling / cost | AWS-managed, $/ALB | you scale pods, 1 LB |
| Portability | AWS-locked | any k8s |

**Hybrid (what this platform runs):** plain `Ingress` uses model A (cheap, simple). When a
route needs API-gateway features or Gateway API, Kong (`envs/prod/02-platform/05-api-gateway`)
is used — but **Kong's own proxy Service is fronted by an ALB (LBC)**, so the two models
chain:
```
Internet → ALB (LBC) → Kong proxy pod → Service → pod
           └ model A ┘  └───────── model B ─────────┘
           TLS/WAF edge   auth · rate-limit · Gateway API (GRPCRoute/HTTPRoute)
```
Rule of thumb: **model A for normal ingress; add Kong (model B behind the ALB) only for
routes that need gateway logic.** Don't run both as *the* gateway for the same route.

**Supporting components:**
- **DNS:** external-dns (`envs/prod/01-addons/03-external-dns`) → Route 53 records.
- **TLS:** cert-manager (`envs/<env>/01-addons/04-cert-manager`) → ACM / Let's Encrypt.
- **WAF:** `envs/<env>/00-infra/07-waf` — attach to an ALB via the Ingress annotation
  `alb.ingress.kubernetes.io/wafv2-acl-arn`.
- **API management:** Kong (`envs/prod/02-platform/05-api-gateway`) behind the LB — rate limiting, auth,
  request transform, versioning.

**Other edge options (beyond ALB/NLB):**
- **Gateway API** — the successor to `Ingress` (LBC supports it); role-split `Gateway` +
  `HTTPRoute`, cleaner for multi-team clusters.
- **CloudFront + WAF/Shield** — CDN/edge cache + DDoS, global entry (not yet in IaC).
- **Kong Gateway API mode** (`envs/prod/02-platform/05-api-gateway`) — the same Kong release can also act as a
  Gateway API implementation (unmanaged `GatewayClass: kong`, reusing the existing
  proxy Service — no new LB). Overlaps LBC — pick one as *the* gateway (classic
  `Ingress` via LBC, or `Gateway`/`HTTPRoute` via Kong).
- **AWS Global Accelerator** — anycast static IPs + cross-region failover in front of NLB/ALB.
- **VPC Lattice** — service-to-service networking across VPCs/accounts without a per-service LB.
- **Internal ALB/NLB (`scheme=internal`) + PrivateLink** — internal-only apps / expose to
  other VPCs/accounts privately.

---

## 2. Outbound (north-south out / egress)

```
Service → [NetworkPolicy] → [Network Firewall / Kuma zone egress] → [NAT (static EIP)] → partner/exchange
```

- **Static egress IP** for partner/exchange source-IP allowlisting: `envs/<env>/00-infra/00-network`
  output `nat_public_ips` (the NAT EIP is what the outside world sees).
- **L3/L4 egress filtering:** NetworkPolicy (`envs/prod/01-addons/07-network-policy`) — pod-level allow/deny.
- **Centralized L7 inspection:** two mutually-exclusive options —
  - **AWS Network Firewall** (`enable_network_firewall` in `00-infra/00-network`) — dedicated firewall
    subnets + app-egress route redirect; domain/FQDN allowlists, IPS. **~$865/mo** — prod only.
  - **Kuma zone egress** (`envs/prod/02-platform/06-service-mesh`) — if the mesh is already in place; policy in-cluster.
- **Skip the NAT for AWS APIs:** VPC endpoints (§4) route ECR/S3/Secrets Manager privately —
  cheaper and works on a fully private cluster.

Egress cost lever: `nat_per_az=false` (one shared NAT, −~$66/mo) vs one NAT per AZ (HA).

---

## 3. Intra-VPC (subnet tiers)

Three subnet tiers per AZ, created by `modules/network` (CIDRs via `cidrsubnet()`):

| Tier | CIDR | Internet route | Holds |
|---|---|---|---|
| **public** | `/20` | via IGW | ALB/NLB, NAT |
| **private-app** | `/20` | via NAT (outbound only) | nodes, pods |
| **private-isolated** | `/24` | **none** | RDS, ElastiCache (reserved) |

Any subnet can reach any other over the VPC **local route** — a **Security Group** is the
real gate (e.g. app→RDS on 5432). "Isolated" means *no internet route*, **not**
unreachable: it's still reachable in-VPC, which is exactly how the app tier talks to it.

---

## 4. VPC endpoints

Keep AWS-service traffic off the NAT (cheaper, and required on a private cluster):

| Endpoint | Type | Cost | Used for |
|---|---|---|---|
| **S3** | gateway | free | ECR image *layers*, tofu state, Loki chunks |
| **ECR** (api + dkr) | interface | hourly + data | image pulls |
| **Secrets Manager** | interface | hourly + data | External Secrets Operator |

Interface endpoints use **private DNS** → an ENI in the app subnet, so SDK calls resolve to
a private IP and never traverse the NAT/IGW.
