# gRPC connection load-balancing lab

A client + server pair that makes the **classic gRPC-on-Kubernetes LB gotcha** visible:
gRPC keeps **one long-lived HTTP/2 connection**, so an L4 Service (ClusterIP) pins every
RPC to a **single backend** — you scale the server to 3 replicas but only 1 gets traffic.
Switch DNS mode + client LB policy and watch the distribution change.

Deployed as **two helm releases** off the shared `charts/app` app chart — each release's
objects come from structured values (`server.yaml` / `client.yaml`), not raw manifests.
The `grpc-debug` namespace is created by helmfile (`createNamespace`), not the chart.
Nodes are **arm64 (Graviton)** — build `arm64`.

## Releases
| Release (`values`) | Renders |
|---|---|
| `grpc-server` (`server.yaml`) | Deployment ×3 (reports `POD_IP`) + Service `grpc-server` (ClusterIP) + Service `grpc-server-headless` (headless) |
| `grpc-client` (`client.yaml`) | Deployment ×1 (REST front-end; `SERVER_ADDR`+`LB_POLICY` pick the case) + Service `grpc-client` (ClusterIP) + ALB Ingress (server stays in-cluster) |

## 0. Prereqs
- A running dev cluster + kubeconfig, the AWS Load Balancer Controller (`01-addons/02`).
- AWS creds for the `default` profile (`../../../../docs/hands-on/AWS-CREDENTIALS.md`).
- ECR repos `grpc-conn-debug/client` + `grpc-conn-debug/server` (in `foundation/02-ecr`):
  ```bash
  (cd ../../../../../foundation/02-ecr && tofu apply)
  ```

## 1. Build both images — **arm64** — and push to ECR
Run from wherever the client/server source lives (each with a `Dockerfile`):
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-southeast-1
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
TAG=v1
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker buildx build --platform linux/arm64 -t "$REGISTRY/grpc-conn-debug/server:$TAG" --push ./server
docker buildx build --platform linux/arm64 -t "$REGISTRY/grpc-conn-debug/client:$TAG" --push ./client
```
> `--platform linux/arm64` is required for the Graviton nodes, else pods crash with
> `exec format error`. More: `../../../../docs/hands-on/PUSH-IMAGE-TO-ECR.md`.

## 2. Set the ECR account id (once) + deploy
`server.yaml` and `client.yaml` pin the image to `ACCOUNT_ID.dkr.ecr…` — the only
per-account value. Replace it in both, then apply the helmfile (both releases):
```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
sed -i "s/ACCOUNT_ID/$ACCT/g" server.yaml client.yaml
helmfile apply --skip-diff-on-install
kubectl -n grpc-debug get pods -o wide          # 3 servers + 1 client, note the IPs
```
The whole dev env (including this layer) also comes up with `cd ../../.. && ./deploy.sh 03-application`.

## 3. The 4 cases — flip and observe
The client's `/call` returns which backend `POD_IP` answered. Hammer it and count the spread:
```bash
kubectl -n grpc-debug port-forward deploy/grpc-client 8080:8080 &
for i in $(seq 1 30); do curl -s localhost:8080/call; echo; done | sort | uniq -c
```

| Case | `SERVER_ADDR` | `LB_POLICY` | Result |
|---|---|---|---|
| **1** | `grpc-server…:50051` (ClusterIP) | `pick_first` | **1 backend** — all 30 hits one pod |
| **2** | `dns:///grpc-server-headless…:50051` | `pick_first` | still 1 (pick_first picks one resolved IP) |
| **3** (default) | `dns:///grpc-server-headless…:50051` | `round_robin` | **spread across all 3** — the fix |
| **4** | ClusterIP (as case 1) | any | per-RPC LB by an **L7 mesh** (Kuma, `02-platform/06`) |

Switch cases by editing the two env vars in `client.yaml` and re-applying, or live:
`kubectl -n grpc-debug set env deploy/grpc-client SERVER_ADDR=… LB_POLICY=…`.

**Takeaway:** on a plain L4 Service, gRPC needs **client-side round-robin over a headless
Service** (case 3) *or* an **L7 proxy/mesh** (case 4) to actually spread load. Case 1 is the
trap most people hit in production.

## 4. Cleanup
```bash
helmfile destroy
# images stay in ECR (immutable); delete the repos via foundation if done for good.
```
