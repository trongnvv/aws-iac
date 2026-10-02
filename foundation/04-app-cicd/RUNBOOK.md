# Runbook — deploy grpc-conn-debug (plan 2: CodePipeline → ECR → ArgoCD)

End-to-end action list. Markers: 🖐️ manual · ⚙️ tofu/automated · ⚠️ attention.
Detailed commands live in the module READMEs referenced below — this is the ordered checklist.

## Prereq (must be done first)
- ⚙️ `00-tf-backend` + `01-dns` applied. 🖐️ set NS records at the registrar (`01-dns` output).
  (`02-ecr` not required — the chart and the grpc images both self-provision their ECR repos.)
- **03-cicd done + chart published** — `helm/app:0.7.0` must exist in ECR (ArgoCD pulls it):
  - 🖐️ authorize the `gitlab` connection (console, during `apply.sh` pause).
  - 🖐️ push `helm-chart-template` → CodeBuild publishes `helm/app`.

## Steps

**A. Push both repos** 🖐️
`grpc-conn-debug` (scrubbed + `buildspec.yml`) and `argo-simple` (apps + values + platform).

**B. Apply CI** ⚙️ — `cd foundation && ./apply.sh` (runs 01→04).
- ⚠️ **03 must be applied before 04** — 04 reads 03's remote state for the connection ARN.
- Creates CodePipeline, CodeBuild, S3 artifact, Pod Identity roles + associations. Reuses the
  connection (no re-authorize).

**C. Enable addon** 🖐️ ⚠️ — `eks-pod-identity-agent` on `eks-dev`. Without it Pod Identity does nothing.

**D. GitLab token → secret** 🖐️ — PAT with `write_repository` on `argo-simple`, then apply the
`repo-argo-simple` secret (argo-simple README §1). This is the only static secret.

**E. ArgoCD → ECR chart auth** ⚙️ — handled by the **ECR credential helper** on argocd-repo-server
(configured in `eks` `02-platform/00-argocd` values, applied by `./deploy.sh 02-platform`).
Identity-based via Pod Identity — no static secret, no CronJob. ⚠️ verify live (helper version,
initContainer image, that Helm OCI honors credHelpers).

**F. Image Updater + apps** — Image Updater is a platform component: ⚙️ `aws-iac/eks`
`./deploy.sh 02-platform` (dir `02-image-updater`). Then 🖐️ `kubectl apply
apps/grpc-conn-debug/{server,client}.yaml` from `argo-simple`.

**G. First run** 🖐️ — push the app repo → CodePipeline builds → image in ECR → Image Updater
bumps the tag → ArgoCD deploys.
- ⚠️ Before the first image exists, values are `d-0000000` → Applications stay unhealthy (expected).

## Attention points
1. **03 before 04** (remote-state dependency).
2. **`eks-pod-identity-agent` addon** is required for all ECR access by ArgoCD pods.
3. **ArgoCD ↔ ECR chart auth** — ECR credential helper (identity, in the argocd values); **verify live**.
4. **Image Updater** `0.12.0` + `write-back-target: helmvalues:` on a multi-source app — **verify live**.
5. ECR repos are **IMMUTABLE** — re-running the same commit pushes no new tag (not an error).

## How the CI/CD works
See the architecture diagram + explanation in `README.md` (this module) and `argo-simple/README.md`.
Short version: push → CodePipeline (Source via connection → S3 → CodeBuild DinD) → 2 images in
ECR → Image Updater polls ECR, commits the new tag to `argo-simple` → ArgoCD pulls the `helm/app`
chart (ECR OCI) + values (git) → syncs to `grpc-debug`.
