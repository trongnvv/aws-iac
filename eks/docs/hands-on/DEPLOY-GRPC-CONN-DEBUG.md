# Hands-on — grpc-conn-debug CI/CD (3 env: build once → promote → deploy)

Build the image once on `main`, then **promote the same digest** through dev → stg → prod by
retagging. CD is ArgoCD (ApplicationSets, one Application per env) + Image Updater (per env).
Markers: 🖐️ manual · ⚙️ tofu/helmfile · ⚠️ attention.

## Flow
```
push main         → CodeBuild build → ECR grpc-conn-debug/*:d-<sha>        → DEV  (auto-sync)
git tag rc-1.1.1  → CodeBuild promote: retag d-<sha> → :rc-1.1.1 (same digest) → STG  (auto-sync)
git tag 1.1.1     → CodeBuild promote: retag → :1.1.1                       → PROD (manual Sync gate)
```
Only `main` builds. `rc-*` / semver git tags **retag** the commit's `d-<sha>` image (`aws ecr
put-image`, no rebuild). Each tag is unique → ECR stays IMMUTABLE.

| Env | ns | Image tag | ImageUpdater allow-tags | ArgoCD sync |
|---|---|---|---|---|
| dev | `dev` | `d-<sha>` | `^d-[0-9a-f]{7}$` | auto |
| stg | `stg` | `rc-1.1.1` | `^rc-` | auto |
| prod | `prod` | `1.1.1` | `^[0-9]+\.[0-9]+\.[0-9]+$` | **manual** |

## Why prod still runs Image Updater (but no auto-sync)
GitOps deploys only when **git** changes. So Image Updater must write the promoted `1.1.1` into
`prod/*-values.yaml` — otherwise ArgoCD has nothing to detect. prod's Application has **no
`automated`** block → ArgoCD shows **OutOfSync** and waits; a human reviews + clicks **Sync** =
the gate. (Image Updater = "what's ready"; manual sync = "when to ship".)

## Components
- **CI** — `foundation/04-app-cicd`: CodePipeline (main → build `d-<sha>`) + CodeBuild
  `grpc-conn-debug-promote` (git-tag webhook → retag). Both share one `buildspec.yml` (mode by trigger).
- **CD** — `gitlab argo-simple/apps/grpc-conn-debug/`: `appset-server.yaml` + `appset-client.yaml`
  (ApplicationSet → 6 Applications), per-env `{dev,stg,prod}/{server,client}-values.yaml` +
  `image-updater.yaml` (ImageUpdater CRs).

## Setup (one-time)
1. ⚙️ foundation base applied + ⚙️ `foundation/apply.sh` (03-cicd connection authorized, 04 CI).
2. 🖐️ enable `eks-pod-identity-agent` on `eks-dev`.
3. ⚙️ `eks` `./deploy.sh 02-platform` — Argo CD + Image Updater (chart 1.3.1, ImageUpdater CRD) +
   the ESO-minted `repo-ecr-helm` OCI repo secret.
4. 🖐️ GitLab token → `repo-argo-simple` secret: fill the token in `argocd-repo-secret.yaml` (this
   dir) and `kubectl apply -f argocd-repo-secret.yaml`. (OCI chart secret `repo-ecr-helm` is ESO-minted.)
5. 🖐️ push repos: `grpc-conn-debug` (one `buildspec.yml` for build+promote) and `argo-simple`.

## Deploy the CD config 🖐️
dev also exposes via Gateway API (`-02`), so deploy the shared gateway-infra (GatewayClass +
LoadBalancerConfiguration in ns `dev`) first: ⚙️ `aws-iac/eks` `./deploy.sh 03-application`.
(stg/prod are ingress-only — no gateway-infra.) Then:
```bash
# from argo-simple
kubectl apply -f apps/grpc-conn-debug/appset-server.yaml
kubectl apply -f apps/grpc-conn-debug/appset-client.yaml
kubectl apply -f apps/grpc-conn-debug/dev/image-updater.yaml
kubectl apply -f apps/grpc-conn-debug/stg/image-updater.yaml
kubectl apply -f apps/grpc-conn-debug/prod/image-updater.yaml
```

## Day-to-day
- **dev**: push `main` → build `d-<sha>` → Image Updater bumps `dev/*-values.yaml` → auto-deploy ns dev.
- **stg**: `git tag rc-1.1.1 && git push --tags` → promote → Image Updater bumps `stg/*` → auto-deploy ns stg.
- **prod**: `git tag 1.1.1 && git push --tags` → promote → Image Updater bumps `prod/*` → ArgoCD
  **OutOfSync** → `argocd app sync grpc-server-prod grpc-client-prod` (or Sync in UI) = gate.

## ⚠️ Verify live (built blind)
- **ApplicationSet** `templatePatch` conditional (prod no `automated`) — verify the prod App has no auto-sync.
- **ImageUpdater CR** schema (v1.x) + git write-back to the per-env values file.
- **promote** (`buildspec.yml` promote mode): `CODEBUILD_WEBHOOK_TRIGGER=tag/<name>` parsing + `put-image` on IMMUTABLE repos.
- Hosts (external-dns, under `*.trongnv.space`): ingress `grpc-{server,client}-<env>.trongnv.space` (all envs)
  + dev Gateway API `grpc-{server,client}-gw-dev.trongnv.space`.
