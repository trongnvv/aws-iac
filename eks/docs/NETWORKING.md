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
Internet → [CloudFront → WAF/Shield] → [ALB / NLB (LBC)] → Service
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

### Target type: `ip` vs `instance`

The target group registers different things depending on target type (set per Service):

**`instance`** — targets are **nodes**, on the Service's **NodePort**.
- Requires `Service type: NodePort` or `LoadBalancer` (a ClusterIP has no NodePort → rejected:
  *"TargetGroup port is empty ... must be of type NodePort or LoadBalancer"*).
- AWS: target group entries = `<instance-id>:<nodePort>`.
- Path: `Client → ALB/NLB → node:NodePort → kube-proxy (iptables/IPVS) → pod` — the pod may be
  on a **different node** (a second hop). The client source IP is SNAT'd away unless
  `externalTrafficPolicy: Local`. Health check hits `node:NodePort`, not each pod.

**`ip`** — targets are **pod IPs**, on the pod's **container port**.
- Works with **any** Service including **ClusterIP** (LBC reads EndpointSlices for the pod IPs).
  Requires routable pod IPs → the **AWS VPC CNI**.
- AWS: target group entries = `<pod-ip>:<containerPort>`.
- Path: `Client → ALB/NLB → pod IP` — straight to the pod's ENI in the VPC, **no NodePort, no
  kube-proxy hop** (lowest latency). ALB terminates so the client IP is in `X-Forwarded-For`;
  an NLB in ip mode preserves the real client IP. Health check hits **each pod IP** (true
  per-pod health) and pairs with the **pod readiness gate** → zero-drop rollouts. LBC
  registers/deregisters pod IPs as pods come and go.

| | `instance` | `ip` |
|---|---|---|
| Target | `node:NodePort` | `pod-ip:containerPort` |
| Service type | NodePort / LoadBalancer | any (**ClusterIP** ok) |
| CNI | any | VPC CNI (routable pod IPs) |
| Data-path hops | ALB → node → kube-proxy → pod (≤2) | ALB → pod (1) |
| Client source IP | SNAT'd unless `externalTrafficPolicy: Local` | X-Forwarded-For (ALB) / preserved (NLB) |
| Health check | per `node:NodePort` | per pod |
| Readiness gate | no | yes |

**This platform uses `ip` everywhere** (Services are ClusterIP; the VPC CNI gives pods real IPs).
How you set it differs by API:
- **Ingress** → annotation `alb.ingress.kubernetes.io/target-type: ip`.
- **Gateway API** → the `TargetGroupConfiguration` CRD (`spec.defaultConfiguration.targetType: ip`)
  attached to the Service. Gateway API does **not** read the Ingress annotation, and the default
  is `instance` — so a ClusterIP Service fails until you add this CRD.

> **Finance/exchange workloads** (FIX, market-data feeds): **NLB** is usually the edge —
> low latency, static EIP for exchange allowlisting, and preserved source IP.

### Two APIs to the ALB — `Ingress` and Gateway API (both via LBC)

The LBC (v3.x) implements **both** the classic `Ingress` API **and** the Kubernetes
Gateway API — each produces a real AWS-managed **ALB**. The controller is *control-plane
only* (not in the data path); traffic goes **straight to pod IPs** (`target-type: ip`).
```
Internet → ALB (AWS-managed, public subnet) → pod IP        [2 hops]
              ▲ LBC programs it from Ingress OR Gateway/HTTPRoute
```

| | `Ingress` (class `alb`) | Gateway API (GatewayClass `alb`) |
|---|---|---|
| Resource | `Ingress` | `Gateway` + `HTTPRoute` / `GRPCRoute` |
| LBC controllerName | `ingress.k8s.aws/alb` | `gateway.k8s.aws/alb` |
| Result | one ALB | one ALB per `Gateway` |
| Ownership | one team owns the Ingress | infra owns `Gateway`, app teams own routes |
| TLS | ACM auto-discover by host | same (listener hostname → ACM) |
| Enable | on by default | LBC feature gate `ALBGatewayAPI=true` + Gateway API CRDs v1.6 |

Both are AWS-native — **no in-cluster proxy**. Prefer `Ingress` for simple single-team
apps; Gateway API when you want the role split (`Gateway` shared, routes per app) or
first-class gRPC routing (`GRPCRoute`).

> **No in-cluster L7 proxy ships in this repo.** If you need gateway *logic* the ALB
> doesn't do (auth, rate-limit, request transform, JWT), add a proxy (Envoy Gateway /
> ingress-nginx / a mesh) behind the ALB yourself — it is not part of the platform.

**Supporting components:**
- **DNS:** external-dns (`envs/prod/01-addons/03-external-dns`) → Route 53 records.
- **TLS:** cert-manager (`envs/<env>/01-addons/04-cert-manager`) → ACM / Let's Encrypt.
- **WAF:** `envs/<env>/00-infra/07-waf` — attach to an ALB via the Ingress annotation
  `alb.ingress.kubernetes.io/wafv2-acl-arn`.
- **Gateway API:** LBC also serves it (GatewayClass `alb`, controllerName
  `gateway.k8s.aws/alb`, feature gate `ALBGatewayAPI`) — `Gateway`/`HTTPRoute`/`GRPCRoute`
  → ALB, same ACM auto-discovery as Ingress.

**Other edge options (beyond ALB/NLB):** *(Gateway API is covered above — LBC serves it natively.)*
- **CloudFront + WAF/Shield** — CDN/edge cache + DDoS, global entry (not yet in IaC).
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
  - **Kuma zone egress** (`envs/prod/02-platform/05-service-mesh`) — if the mesh is already in place; policy in-cluster.
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
