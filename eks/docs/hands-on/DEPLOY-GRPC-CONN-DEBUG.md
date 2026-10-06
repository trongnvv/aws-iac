# Hands-on — grpc-conn-debug CI/CD (3 env: build once → promote → deploy)

Build the image once on `main`, then **promote the same digest** through dev → stg → prod by
retagging. **CI commits the image tag into the gitops repo** (push model); CD is ArgoCD
(ApplicationSets, one Application per env) syncing git. No Image Updater.
Markers: 🖐️ manual · ⚙️ tofu/helmfile · ⚠️ attention.

## Flow
```
push main         → CodeBuild build → ECR grpc-conn-debug/*:d-<sha> → CI commits d-<sha>  → DEV  (auto-sync)
git tag rc-1.1.1  → CodeBuild promote: retag → :rc-1.1.1            → CI commits rc-1.1.1 → STG  (auto-sync)
git tag 1.1.1     → CodeBuild promote: retag → :1.1.1              → CI commits 1.1.1    → PROD (manual Sync gate)
```
Only `main` builds. `rc-*` / semver git tags **retag** the commit's `d-<sha>` image (`aws ecr
put-image`, no rebuild). Each tag is unique → ECR stays IMMUTABLE. After build/retag, the same
buildspec writes the tag into `{env}/*-values.yaml` and pushes.

| Env | ns | Image tag | CI commits to | ArgoCD sync |
|---|---|---|---|---|
| dev | `dev` | `d-<sha>` | `dev/*-values.yaml` | auto |
| stg | `stg` | `rc-1.1.1` | `stg/*-values.yaml` | auto |
| prod | `prod` | `1.1.1` | `prod/*-values.yaml` | **manual** |

## Why prod is a gate
GitOps deploys only when **git** changes. CI commits the promoted `1.1.1` into `prod/*-values.yaml`;
prod's Application has **no `automated`** block → ArgoCD shows **OutOfSync** and waits; a human
reviews + clicks **Sync** = the gate. (CI commit = "what's ready"; manual sync = "when to ship".)

## Components
- **CI** — `foundation/04-app-cicd`: CodePipeline (main → build `d-<sha>`) + CodeBuild
  `grpc-conn-debug-promote` (git-tag webhook → retag). Both share one `buildspec.yml` (mode by
  trigger); its `post_build` commits the tag into the gitops repo using the GitLab deploy token.
- **CD** — `gitlab argo-simple/apps/grpc-conn-debug/`: `appset-server.yaml` + `appset-client.yaml`
  (ApplicationSet → 6 Applications) + per-env `{dev,stg,prod}/{server,client}-values.yaml`.

## Setup (one-time)
1. ⚙️ foundation base applied + ⚙️ `foundation/apply.sh` (03-cicd connection authorized, 04 CI).
2. 🖐️ enable `eks-pod-identity-agent` on `eks-dev`.
3. 🖐️ **GitLab deploy token** on `gitops/argo-simple` (scopes `read_repository` + `write_repository`)
   → store in Secrets Manager `prod/gitlab-argo-simple-token` as JSON
   `{"username":"gitlab+deploy-token-N","password":"gldt-..."}`. One secret for CI write + ArgoCD read.
4. ⚙️ `eks` `./deploy.sh 02-platform` — Argo CD + ESO-minted secrets: `repo-ecr-helm` (OCI chart) +
   `repo-argo-simple` (git, from the Secrets Manager deploy token). Nothing to `kubectl apply`.
5. 🖐️ push repos: `grpc-conn-debug` (one `buildspec.yml` for build+promote+commit) and `argo-simple`.

## Deploy the CD config 🖐️
dev also exposes via Gateway API (`-02`), so deploy the shared gateway-infra (GatewayClass +
LoadBalancerConfiguration in ns `dev`) first: ⚙️ `aws-iac/eks` `./deploy.sh 03-application`.
(stg/prod are ingress-only — no gateway-infra.) Then apply the **root app-of-apps** once — Argo CD
syncs every appset under `apps/` (grpc + hello) and re-creates them on re-setup:
```bash
# from argo-simple
kubectl apply -f bootstrap/root-app.yaml
kubectl -n argocd get applicationset,applications
```

## Day-to-day
- **dev**: push `main` → build `d-<sha>` → CI commits `dev/*-values.yaml` → auto-deploy ns dev.
- **stg**: `git tag rc-1.1.1 && git push --tags` → promote → CI commits `stg/*` → auto-deploy ns stg.
- **prod**: `git tag 1.1.1 && git push --tags` → promote → CI commits `prod/*` → ArgoCD **OutOfSync**
  → `argocd app sync grpc-server-prod grpc-client-prod` (or Sync in UI) = gate.

## ⚠️ Verify live (built blind)
- **ApplicationSet** `templatePatch` conditional (prod no `automated`) — verify the prod App has no auto-sync.
- **CI git-commit** (`buildspec.yml` post_build): deploy-token clone + `sed` tag bump + push to `argo-simple`.
- **promote** (`buildspec.yml` promote mode): `CODEBUILD_WEBHOOK_TRIGGER=tag/<name>` parsing + `put-image` on IMMUTABLE repos.
- Hosts (external-dns, under `*.trongnv.space`): ingress `grpc-{server,client}-<env>.trongnv.space` (all envs)
  + dev Gateway API `grpc-{server,client}-gw-dev.trongnv.space`.
