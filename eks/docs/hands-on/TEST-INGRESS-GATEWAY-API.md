# Test — Ingress vs Gateway API, REST vs gRPC

Compares the two north-south entry points the platform can use (classic `Ingress` via
the AWS Load Balancer Controller vs `Gateway API` via Istio) against both a REST and a
gRPC backend. 4 combinations; the interesting contrast is how each handles gRPC.

> 💸 Creates an ALB (or two). Clean up (§5) when done — see `docs/TROUBLESHOOTING.md`
> if a `kubectl delete` hangs on a `LoadBalancer`/`Ingress` finalizer.

## 0. Prereqs
- Cluster up, `layer1-addons/02-aws-load-balancer-controller` applied (in both `dev`
  and `prod` presets already).
- A domain + ACM cert from `../../../foundation/01-dns` if you want real TLS; otherwise
  port-forward / `curl --resolve` against the ALB hostname.
- REST backend: `traefik/whoami` (public, multi-arch — no ECR push needed).
- gRPC backend: reuse `../../ad-hoc/grpc-conn-debug/` (already builds arm64 images to
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

## 2. Case B — REST through Gateway API (Istio)
Gateway API CRDs aren't installed by any layer yet (Istio only ships `base` + `istiod`
in `layer2-platform/06-service-mesh`) — install them once for this test:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
kubectl get gatewayclass   # "istio" should appear once istiod restarts and sees the CRDs
```
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw
spec:
  gatewayClassName: istio
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
kubectl get svc gw-istio -w   # Istio provisions its own LoadBalancer Service (an NLB by default, not ALB)
curl "$(kubectl get svc gw-istio -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

## 3. Case C — gRPC through classic Ingress (ALB)
ALB supports gRPC, but only over **HTTPS** (needs ALPN h2) — plug in the ACM cert:
```bash
CERT_ARN=$(cd ../../../foundation/01-dns && tofu output -raw acm_certificate_arn)
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
up with an L4 `ClusterIP` *inside* the cluster (see `../../ad-hoc/grpc-conn-debug/`).

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
  gatewayClassName: istio
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
Hammer it like in the base lab (§4 there) and confirm Istio's L7 proxy spreads load
across all 3 server pods without any client-side `round_robin` config — the mesh does
what case 3/4 of the base lab needed the client or Istio to do manually.

## 5. Comparison

| | Classic Ingress (ALB) | Gateway API (Istio) |
|---|---|---|
| REST | Works out of the box | Works, provisions its own LB (not the ALB Controller) |
| gRPC | Needs `backend-protocol-version: GRPC` annotation + HTTPS listener | Native `GRPCRoute` kind, protocol-aware by design |
| Load balancer | Always ALB | Whatever the Gateway class provisions (NLB here) |
| Portability | AWS-specific annotations | Same YAML works on any Gateway API implementation |

## 6. Cleanup
```bash
kubectl delete ingress whoami; kubectl delete deploy,svc whoami
kubectl delete gateway gw; kubectl delete httproute whoami
kubectl -n grpc-debug delete ingress grpc-server
kubectl -n grpc-debug delete gateway grpc-gw; kubectl -n grpc-debug delete grpcroute grpc-server
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```
