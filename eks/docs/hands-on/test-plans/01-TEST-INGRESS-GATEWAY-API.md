# Test — Ingress vs Gateway API, REST vs gRPC

Compares the two north-south entry points the platform can use — classic `Ingress` vs the
**Kubernetes Gateway API** — both served by the **AWS Load Balancer Controller** and both
provisioning an **ALB** (no in-cluster proxy). 4 combinations; the interesting contrast is
the resource model (single `Ingress` vs role-split `Gateway`+route) and how each handles gRPC.

> 💸 Each `Ingress` and each `Gateway` provisions its own ALB. Clean up (§5) when done —
> see `docs/TROUBLESHOOTING.md` if a `kubectl delete` hangs on a finalizer.

## 0. Prereqs
- Cluster up, `envs/<env>/01-addons/02-aws-load-balancer-controller` applied (both presets).
- **Gateway API enabled on the LBC** (cases B/D): feature gate `ALBGatewayAPI=true` in the
  LBC chart values (`envs/<env>/01-addons/02-aws-load-balancer-controller/values.yaml`:
  `featureGates: {ALBGatewayAPI: true}`), then `helmfile apply`.
- **Gateway API CRDs — two groups, only ONE is installed by hand:**
  - **Upstream Gateway API** (`gateway.networking.k8s.io`: GatewayClass/Gateway/HTTPRoute/GRPCRoute)
    — not bundled anywhere; `envs/<env>/deploy.sh` installs it (server-side, in the wire-kubeconfig
    step), or standalone:
    ```bash
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
    ```
  - **LBC CRDs** (`gateway.k8s.aws`: LoadBalancerConfiguration/TargetGroupConfiguration/ListenerRuleConfiguration)
    — **ship with the LBC Helm chart** (`01-addons/02`), created on first `helmfile apply`. No separate step.
- A domain + ACM cert from `../../../../foundation/01-dns` for real TLS; otherwise
  port-forward / `curl --resolve` against the ALB hostname.
- REST backend: `traefik/whoami` (public, multi-arch — no ECR push needed).
- gRPC backend: reuse `../../../envs/dev/03-application/00-grpc-debug/`; this test only
  changes how it's **exposed**, not the app.

## 1. Case A — REST through classic Ingress (ALB)
```bash
kubectl create deployment whoami --image=traefik/whoami
kubectl expose deployment whoami --port=80
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: whoami, port: { number: 80 } } }
EOF
kubectl get ingress whoami -w   # wait for ADDRESS
curl "$(kubectl get ingress whoami -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

## 2. Case B — REST through Gateway API (ALB)
The LBC serves the Gateway API too. Create a `GatewayClass` pointing at the LBC's gateway
controller, a `LoadBalancerConfiguration` for ALB settings (scheme), a `Gateway` (→ one ALB),
and an `HTTPRoute`:
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: alb
spec:
  controllerName: gateway.k8s.aws/alb
---
# LBC CRD (group gateway.k8s.aws) — ALB scheme / TLS / attributes. Attached to the Gateway
# via infrastructure.parametersRef. v1 is the storage version in LBC v3.5.
apiVersion: gateway.k8s.aws/v1
kind: LoadBalancerConfiguration
metadata:
  name: internet-facing
spec:
  scheme: internet-facing
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw
spec:
  gatewayClassName: alb
  infrastructure:
    parametersRef: { group: gateway.k8s.aws, kind: LoadBalancerConfiguration, name: internet-facing }
  listeners:
    - name: http
      port: 80
      protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
spec:
  parentRefs: [{ name: gw }]
  rules:
    - backendRefs: [{ name: whoami, port: 80 }]
EOF
kubectl get gateway gw -w   # wait for ADDRESS = a NEW ALB (one ALB per Gateway)
curl "$(kubectl get gateway gw -o jsonpath='{.status.addresses[0].value}')"
```

## 3. Case C — gRPC through classic Ingress (ALB)
ALB supports gRPC, but only over **HTTPS** (needs ALPN h2) — plug in the ACM cert:
```bash
CERT_ARN=$(cd ../../../../foundation/01-dns && tofu output -raw regional_cert_arn)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grpc-server
  namespace: grpc-debug
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol-version: GRPC
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: $CERT_ARN
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: grpc-server, port: { number: 50051 } } }
EOF
grpcurl -d '{}' "$(kubectl -n grpc-debug get ingress grpc-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):443" list
```
**Gotcha to observe:** the ALB is L7 but still opens **one HTTP/2 connection per client**,
so it doesn't reproduce the pinning bug from the base lab — that only shows up with an L4
`ClusterIP` *inside* the cluster (see `../../../envs/dev/03-application/00-grpc-debug/`).

## 4. Case D — gRPC through Gateway API (`GRPCRoute`)
Gateway API has a **native `GRPCRoute` kind** (GA since v1.1) — no vendor annotation. LBC
v3.5 provisions the ALB. gRPC over the ALB needs HTTPS, and here the LBC + upstream CRD have a
**TLS quirk**: the CRD requires `tls.certificateRefs` **or** `tls.options` for a `Terminate`
listener, but the LBC ignores both — you pass a **dummy `tls.options`** to satisfy CRD
validation and set the real cert in the `LoadBalancerConfiguration.listenerConfigurations[].defaultCertificate`:
```bash
CERT_ARN=$(cd ../../../../foundation/01-dns && tofu output -raw regional_cert_arn)
kubectl get crd grpcroutes.gateway.networking.k8s.io   # present after the v1.6 CRD apply
kubectl apply -f - <<EOF
apiVersion: gateway.k8s.aws/v1
kind: LoadBalancerConfiguration
metadata:
  name: internet-facing
  namespace: grpc-debug
spec:
  scheme: internet-facing
  listenerConfigurations:
    - protocolPort: HTTPS:443
      defaultCertificate: $CERT_ARN     # the ALB's cert (LBC ignores the listener's certificateRefs)
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: grpc-gw
  namespace: grpc-debug
spec:
  gatewayClassName: alb
  infrastructure:
    parametersRef: { group: gateway.k8s.aws, kind: LoadBalancerConfiguration, name: internet-facing }
  listeners:
    - name: grpc
      port: 443
      protocol: HTTPS
      hostname: "grpc-server.trongnv.space"
      tls:
        mode: Terminate
        options: { pass-crd-validation: "true" }   # no-op for the LBC; only gets past CRD validation
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-server
  namespace: grpc-debug
spec:
  parentRefs: [{ name: grpc-gw }]
  hostnames: ["grpc-server.trongnv.space"]
  rules:
    - backendRefs: [{ name: grpc-server, port: 50051 }]
EOF
```
> **TLS quirk:** the upstream Gateway API CRD enforces `certificateRefs` OR `options` for
> `mode: Terminate`; the LBC uses neither (the cert comes from the `LoadBalancerConfiguration`).
> The `pass-crd-validation` option is a no-op purely to get past CRD validation.

Hammer it and confirm the ALB L7-routes each RPC across all 3 server pods — the Gateway does
the spread the base lab needed the client to do (case 3/4). This is a *gateway* doing
east-west LB on ingress, not a mesh — compare against Kuma
(`envs/prod/02-platform/05-service-mesh`) doing it sidecar-to-sidecar.

## 5. Comparison

| | Classic Ingress (ALB) | Gateway API (ALB) |
|---|---|---|
| Resource | one `Ingress` | `Gateway` + `HTTPRoute`/`GRPCRoute` (role split) |
| Controller | `ingress.k8s.aws/alb` | `gateway.k8s.aws/alb` |
| Load balancer | one ALB per Ingress | one ALB per `Gateway` |
| gRPC | `backend-protocol-version: GRPC` annotation + HTTPS | native `GRPCRoute` kind, protocol-aware |
| ALB config | annotations | `LoadBalancerConfiguration` CRD via `parametersRef` |
| Portability | AWS-specific annotations | route YAML portable; `GatewayClass`/params are AWS-specific |

Both are AWS-native (LBC → ALB). Gateway API wins on the role split and first-class gRPC;
Ingress wins on being simplest for a single-team app.

## 6. Cleanup
```bash
kubectl delete ingress whoami; kubectl delete deploy,svc whoami
kubectl delete httproute whoami; kubectl delete gateway gw
kubectl -n grpc-debug delete ingress grpc-server
kubectl -n grpc-debug delete grpcroute grpc-server; kubectl -n grpc-debug delete gateway grpc-gw
kubectl delete loadbalancerconfiguration internet-facing
kubectl delete gatewayclass alb
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
```

---

## Appendix — how the AWS Load Balancer Controller maps to AWS

Reference for the two paths above. Applies to LBC v3.5 (Gateway API GA since v3.0.0, Mar 2026).

### A1. How the LBC works (Ingress / Service)
The LBC runs in the cluster, watches Kubernetes resources, and calls AWS APIs to create/manage ALBs & NLBs.

Resource → AWS:
- `Ingress` (ingressClass `alb`) → **ALB** (L7). Rules/paths → listener rules; backend Service → target group.
- `Service type: LoadBalancer` (`loadBalancerClass: service.k8s.aws/nlb`, or annotation `service.beta.kubernetes.io/aws-load-balancer-type: external`) → **NLB** (L4).
- CRD `TargetGroupBinding` → bind a Service to a **pre-existing** target group (LB owned by Terraform / another team); LBC only syncs targets.

Reconcile loop: watch Ingress/Service/EndpointSlices → build a model (LB, listeners, rules, target groups, SGs) → diff vs real AWS state → call ELBv2/EC2 APIs → register/deregister targets as pods change.

Target type:
- `instance`: target = node:NodePort, traffic via kube-proxy (extra hop, loses source IP unless configured).
- `ip`: target = **pod IP directly** (needs the VPC CNI; pod IPs routable in the VPC). No NodePort hop, lower latency, per-pod health checks.

Supporting pieces: IAM via IRSA / Pod Identity; subnet discovery via tags `kubernetes.io/role/elb` (public) / `kubernetes.io/role/internal-elb` (internal); a mutating webhook injects a **pod readiness gate** (a pod is Ready only once its target is healthy on the LB → no traffic drop during rollout); `IngressGroup` (`group.name`) lets many Ingresses share one ALB.

Traffic (ip mode): `Client → ALB/NLB → pod IP (ENI in the VPC)` — not via kube-proxy.

> Not usable on-prem (depends on AWS APIs + the VPC). On-prem equivalent: MetalLB / Cilium LB IPAM (L4) + an ingress controller like NGINX (L7).

### A2. LBC with Gateway API
Same controller, same reconcile loop — the input is Gateway API resources instead of Ingress + annotations.

Resource → AWS:
- `GatewayClass` `controllerName`: `gateway.k8s.aws/alb` → ALB (L7); `gateway.k8s.aws/nlb` → NLB (L4).
- `Gateway` → one ALB or NLB; each `listeners[]` → a listener; the LB DNS lands in `status.addresses`.
- `HTTPRoute`/`GRPCRoute` → ALB; `TCPRoute`/`UDPRoute`/`TLSRoute` → NLB. Matches/filters → listener rules; `backendRefs` → target groups.

Config via CRDs (validated at apply, unlike JSON-in-annotations):
- `LoadBalancerConfiguration` — scheme, subnets, SGs… attached to Gateway/GatewayClass.
- `TargetGroupConfiguration` — target type, health check, attributes, per Service.
- `ListenerRuleConfiguration` — ALB-specific actions/conditions the spec lacks (e.g. OIDC/Cognito auth).

Vs Ingress: **role split** — the platform team owns GatewayClass/Gateway (the LB), app teams write Routes in their own namespace; cross-namespace via `allowedRoutes` + `ReferenceGrant` (no IngressGroup needed). Many Routes on one Gateway share one LB. IAM, subnet discovery, target type, readiness gate — unchanged.

Notes: install the upstream Gateway API CRDs first; enable feature gate `ALBGatewayAPI` / `NLBGatewayAPI` as needed. Don't confuse with the **AWS Gateway API Controller (VPC Lattice)** — a separate controller for east-west service-to-service; the LBC does north-south via ALB/NLB.

### A3. ALB vs NLB object model
Both are ELBv2, same tree: `Load Balancer → Listener → (Rule) → Target Group → Target`.

**ALB (L7, proxy):**
- LB: nodes with an ENI per AZ; auto-scales so IPs change → use the DNS name. Has a **Security Group**; integrates WAF/Shield.
- Listener: HTTP/HTTPS; HTTPS holds ACM certs (multiple via SNI) + SSL policy.
- Listener Rule (ALB's core), priority-ordered: *conditions* (host, path, header, method, query, source IP); *actions* (`forward` to one/many weighted TGs, `redirect`, `fixed-response`, `authenticate-oidc/cognito`); always a **default action**.
- Target Group: type `instance`/`ip`/`lambda`; HTTP/HTTPS/gRPC; health check + attributes (deregistration delay, stickiness, slow start, algorithm: round-robin / least-outstanding-requests).
- Behavior: terminates the connection, opens a new one to the backend; client IP via `X-Forwarded-For` (network source IP = the ALB node).

**NLB (L4, pass-through):**
- LB: **static IP per AZ** (assignable EIP); cross-zone off by default; SG supported (enabled at creation).
- Listener: TCP / UDP / TCP_UDP / TLS (TLS terminates with ACM).
- **No rules** — each listener just default-forwards to one TG.
- Target Group: type `instance`/`ip`/`alb` (NLB in front of an ALB); health check TCP/HTTP/HTTPS; attributes (client IP preservation, proxy protocol v2, deregistration delay).
- Behavior: flow-hash (a flow always hits the same target); preserves client IP; lowest latency.

**In short:** ALB = rich L7 routing; NLB = static IP, client-IP preservation, plain L4.

### A4. What each Gateway API resource creates in AWS

| K8s resource | What it creates in AWS |
|---|---|
| `GatewayClass` | **Nothing** — just selects the alb/nlb controller. |
| `LoadBalancerConfiguration` | **No own object** — LB attributes: scheme, subnets, SG, IP type, access logs, deletion protection (listener cert / SSL policy too; field names vary by version). |
| `Gateway` | **Load Balancer** + **Listener** (one per port; same port + different hostname → one listener with SNI certs) + **Security Groups** LBC manages (frontend SG on the LB, backend SG + inbound rule to nodes/pods) + a default action (usually fixed-response 404). |
| `HTTPRoute` / `GRPCRoute` | **Listener Rule** on the listener the `parentRefs`/`sectionName` points to. `hostnames` + `matches` → conditions; `backendRefs` → **Target Group** (one per Service:port; weights → weighted forward); `RequestRedirect` → redirect action. |
| `TCPRoute` / `UDPRoute` / `TLSRoute` | **Target Group** as the NLB listener's default forward. No rules. |
| `TargetGroupConfiguration` | **No own object** — sets a Service's TG attributes: target type, health check, stickiness, deregistration delay, proxy protocol. |
| `ListenerRuleConfiguration` | **No own object** — adds actions/conditions to the rule generated from an HTTPRoute (OIDC auth, source-IP…), attached via a filter `ExtensionRef`. |
| `Service` / `EndpointSlice` | **Register/deregister Targets** (pod IP or node:NodePort) in the TG. LBC uses TargetGroupBinding internally. |
| `ReferenceGrant` | **Nothing in AWS** — a K8s-side permission only. |

Quick mnemonic:
```
Gateway   → LB + Listener + SG
Route     → Rule + Target Group
Service   → Targets
*Configuration                  → just attributes of the objects above
GatewayClass / ReferenceGrant   → K8s-side meaning only
```
