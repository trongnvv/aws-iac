# Test — Ingress vs Gateway API, REST vs gRPC

Compares the two north-south entry points the platform can use (classic `Ingress` via
the AWS Load Balancer Controller vs `Gateway API` via Kong, `envs/prod/02-platform/05-api-gateway`) against both a
REST and a gRPC backend. 4 combinations; the interesting contrast is how each handles
gRPC — and how Kong's Gateway API mode differs from a mesh's (no new load balancer).

> 💸 Creates an ALB (or two). Clean up (§5) when done — see `docs/TROUBLESHOOTING.md`
> if a `kubectl delete` hangs on a `LoadBalancer`/`Ingress` finalizer.

## 0. Prereqs
- Cluster up, `envs/<env>/01-addons/02-aws-load-balancer-controller` applied (in both `dev`
  and `prod` presets already), and `envs/prod/02-platform/05-api-gateway` (Kong) applied for
  cases B/D.
- A domain + ACM cert from `../../../../foundation/01-dns` if you want real TLS; otherwise
  port-forward / `curl --resolve` against the ALB hostname.
- REST backend: `traefik/whoami` (public, multi-arch — no ECR push needed).
- gRPC backend: reuse `../../../ad-hoc/grpc-conn-debug/` (already builds arm64 images to
  the shared ECR); this test only changes how it's **exposed**, not the app.

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

## 2. Case B — REST through Gateway API (Kong)
Gateway API CRDs aren't installed by any layer yet, and — unlike Istio — Kong doesn't
auto-register a `GatewayClass` either. Install the CRDs, then create the class once,
pointing it at Kong's controller in **unmanaged** mode (reuse the existing `kong`
proxy Service instead of provisioning a new load balancer per `Gateway`):

> **Gateway API version:** pin to **v1.3** — the newest the bundled KIC 3.5
> (`kong/kong` chart 3.4.1) officially supports (matrix: v1.0–v1.3). Don't jump to
> v1.6; it's outside Kong's tested range for this chart. See `docs/VERSION-COMPATIBILITY.md`.
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong
  annotations:
    konghq.com/gatewayclass-unmanaged: "true"
spec:
  controllerName: konghq.com/kic-gateway-controller
EOF
kubectl get gatewayclass kong
```
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw
spec:
  gatewayClassName: kong
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
kubectl get svc -n kong kong-kong-proxy   # unmanaged mode: no new LB — routes land on the existing shared Kong proxy
curl "$(kubectl get svc -n kong kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

## 3. Case C — gRPC through classic Ingress (ALB)
ALB supports gRPC, but only over **HTTPS** (needs ALPN h2) — plug in the ACM cert:
```bash
CERT_ARN=$(cd ../../../../foundation/01-dns && tofu output -raw acm_certificate_arn)
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
**Gotcha to observe:** the ALB is L7 but still opens **one HTTP/2 connection per
client**, so it doesn't reproduce the pinning bug from the base lab — that only shows
up with an L4 `ClusterIP` *inside* the cluster (see `../../../ad-hoc/grpc-conn-debug/`).

## 4. Case D — gRPC through Gateway API (`GRPCRoute`)
This is the real differentiator: Gateway API has a **native `GRPCRoute` kind**, no
vendor annotation needed. Check it's available first (may be `experimental` channel
depending on the installed version):
```bash
kubectl get crd grpcroutes.gateway.networking.k8s.io
```
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: grpc-gw
  namespace: grpc-debug
spec:
  gatewayClassName: kong
  listeners:
    - name: grpc
      port: 50051
      protocol: HTTP   # h2c; add TLS listener for real HTTPS/2
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
> Needs Kong Ingress Controller ≥ 3.2 (Gateway API v1 `GRPCRoute`); check
> `kubectl get pods -n kong -o jsonpath='{.items[0].spec.containers[*].image}'` if this
> doesn't reconcile.

Hammer it like in the base lab (§4 there) and confirm Kong's L7 proxy spreads load
across all 3 server pods without any client-side `round_robin` config — the gateway
does what case 3/4 of the base lab needed the client to do manually. (This is a
*gateway* doing east-west LB on its way in, not the mesh — compare against Kuma
`envs/prod/02-platform/06-service-mesh` doing the same job sidecar-to-sidecar, no gateway involved.)

## 5. Comparison

| | Classic Ingress (ALB) | Gateway API (Kong) |
|---|---|---|
| REST | Works out of the box | Works, routes onto the existing `kong-kong-proxy` Service — no new LB (unmanaged `GatewayClass`) |
| gRPC | Needs `backend-protocol-version: GRPC` annotation + HTTPS listener | Native `GRPCRoute` kind (KIC ≥ 3.2), protocol-aware by design |
| Load balancer | Always ALB | None new — reuses the Kong proxy Service already created by `envs/prod/02-platform/05-api-gateway` |
| Portability | AWS-specific annotations | Same YAML works on any Gateway API implementation |
| Setup | `GatewayClass` auto-registered by the controller | Must create the `GatewayClass` yourself (unmanaged mode) |

## 6. Cleanup
```bash
kubectl delete ingress whoami; kubectl delete deploy,svc whoami
kubectl delete gateway gw; kubectl delete httproute whoami
kubectl -n grpc-debug delete ingress grpc-server
kubectl -n grpc-debug delete gateway grpc-gw; kubectl -n grpc-debug delete grpcroute grpc-server
kubectl delete gatewayclass kong
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```
