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
- **Gateway API CRDs — TWO sets** (LBC needs both):
  ```bash
  # 1. upstream Gateway API (gateway.networking.k8s.io) — GatewayClass/Gateway/HTTPRoute/GRPCRoute
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml
  # 2. LBC CRDs (gateway.k8s.aws) — LoadBalancerConfiguration/TargetGroupConfiguration/ListenerRuleConfiguration
  #    use the tag matching the controller (v3.5.0), NOT refs/heads/main; skip if the chart already installed them
  kubectl get crd loadbalancerconfigurations.gateway.k8s.aws >/dev/null 2>&1 \
    || kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/config/crd/gateway/gateway-crds.yaml
  ```
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
v3.5 provisions the ALB from it. gRPC over the ALB needs HTTPS, so give the listener a cert
(auto-discovered from ACM by hostname, or set `defaultCertificate` in the
`LoadBalancerConfiguration`):
```bash
kubectl get crd grpcroutes.gateway.networking.k8s.io   # present after the v1.6 CRD apply
kubectl apply -f - <<'EOF'
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
      hostname: "grpc-server.trongnv.space"   # LBC auto-discovers the *.trongnv.space ACM cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: grpc-server
  namespace: grpc-debug
spec:
  parentRefs: [{ name: grpc-gw }]
  rules:
    - backendRefs: [{ name: grpc-server, port: 50051 }]
EOF
```
(The `LoadBalancerConfiguration internet-facing` from Case B must exist in this namespace too,
or reference one in scope.)

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
