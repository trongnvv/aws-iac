# gRPC connection load-balancing lab

A client + server pair that makes the **classic gRPC-on-Kubernetes LB gotcha** visible:
gRPC keeps **one long-lived HTTP/2 connection**, so an L4 Service (ClusterIP) pins every
RPC to a **single backend** — you scale the server to 3 replicas but only 1 gets traffic.
The lab lets you switch DNS mode + client LB policy and watch the distribution change.

> 💻 This folder is deployable manifests. Images are built by hand (below) and pushed to
> the shared ECR (`foundation/02-ecr`). Nodes are **arm64 (Graviton)** — build `arm64`.

## Files
| File | What |
|---|---|
| `server-deployment.yaml` | gRPC server, 3 replicas, reports its `POD_IP` so you can see which backend answered |
| `server-service.yaml` | **ClusterIP** (`grpc-server`) + **headless** (`grpc-server-headless`) |
| `client-deployment.yaml` | client with a REST front-end; `SERVER_ADDR` + `LB_POLICY` pick the case |
| `client-service.yaml` | ClusterIP for the client REST API |
| `ingress.yaml` | ALB Ingress exposing the client REST (server stays in-cluster) |
| `kustomization.yaml` | wires it together + sets the ECR image refs |

## 0. Prereqs
- A running cluster + kubeconfig (`../../docs/DEPLOY.md`), `kubectl`, `kustomize`, Docker/Podman.
- AWS creds for the `default` profile (`../../docs/hands-on/AWS-CREDENTIALS.md`).
- The AWS Load Balancer Controller from `layer1/02` (for the Ingress).

## 1. Create the ECR repos (once)
Already added to `foundation/02-ecr` `repo_names` as `grpc-conn-debug/client` +
`grpc-conn-debug/server`. Apply the foundation to create them:
```bash
(cd ../../../foundation/02-ecr && tofu apply)
```

## 2. Build both images by hand — **arm64**
Run from wherever the client/server source lives (each with a `Dockerfile`). Generic build:
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-southeast-1
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
TAG=v1

# log Docker in to ECR
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# server (build for the Graviton nodes; buildx builds AND pushes)
docker buildx build --platform linux/arm64 \
  -t "$REGISTRY/grpc-conn-debug/server:$TAG" --push ./server

# client
docker buildx build --platform linux/arm64 \
  -t "$REGISTRY/grpc-conn-debug/client:$TAG" --push ./client
```
> Building on an amd64 laptop for arm64 nodes is exactly why `--platform linux/arm64` is
> required — otherwise pods crash with `exec format error`. More detail:
> `../../docs/hands-on/PUSH-IMAGE-TO-ECR.md`.

Verify:
```bash
aws ecr describe-images --repository-name grpc-conn-debug/server --region "$REGION" \
  --query 'imageDetails[].imageTags'
```

## 3. Deploy
Point kustomize at your ECR, then apply:
```bash
kustomize edit set image \
  grpc-server="$REGISTRY/grpc-conn-debug/server:$TAG" \
  grpc-client="$REGISTRY/grpc-conn-debug/client:$TAG"

kubectl apply -k .
kubectl -n grpc-debug get pods -o wide          # 3 servers + 1 client, note the IPs
```
Edit `ingress.yaml` host (`grpc-client-lab-01.example.com`) to your real domain first if you
want external DNS; otherwise just port-forward the client in step 4.

## 4. The 4 cases — flip and observe
The client’s `/call` returns which backend `POD_IP` answered. Hammer it and count the spread:
```bash
kubectl -n grpc-debug port-forward deploy/grpc-client 8080:8080 &
for i in $(seq 1 30); do curl -s localhost:8080/call; echo; done | sort | uniq -c
```

| Case | `SERVER_ADDR` | `LB_POLICY` | Result |
|---|---|---|---|
| **1** (default) | `grpc-server…:50051` (ClusterIP) | `pick_first` | **1 backend** — all 30 hits one pod |
| **2** | `dns:///grpc-server-headless…:50051` | `pick_first` | still 1 (pick_first picks one resolved IP) |
| **3** | `dns:///grpc-server-headless…:50051` | `round_robin` | **spread across all 3** — the fix |
| **4** | ClusterIP (as case 1) | any | per-RPC LB by an **L7 mesh** (Kuma, `layer2/06`) |

Switch cases by editing the two env vars in `client-deployment.yaml` and re-applying (or
`kubectl -n grpc-debug set env deploy/grpc-client SERVER_ADDR=… LB_POLICY=…`).

**Takeaway:** on a plain L4 Service, gRPC needs **client-side round-robin over a headless
Service** (case 3) *or* an **L7 proxy/mesh** (case 4) to actually spread load. Case 1 is the
trap most people hit in production.

## 5. Cleanup
```bash
kubectl delete -k .
# images stay in ECR (immutable); delete the repos via foundation if done for good.
```
