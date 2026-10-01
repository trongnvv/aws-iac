# Runbook — deploy grpc-conn-debug (plan 2: CodePipeline → ECR → ArgoCD)

End-to-end action list. Markers: 🖐️ manual · ⚙️ tofu/automated · ⚠️ attention.
Detailed commands live in the module READMEs referenced below — this is the ordered checklist.

## Prereq (must be done first)
- ⚙️ `00-tf-backend`, `01-dns`, `02-ecr` applied. 🖐️ set NS records at the registrar (`01-dns` output).
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

**E. ArgoCD → ECR chart auth** ⚠️ — pulling the `helm/app` OCI chart needs auth:
- Current files use a **CronJob refresh** (argo-simple README §2) — ⚠️ fix the CronJob image to one with aws-cli + kubectl.
- **Recommended:** switch to the **ECR credential helper** (identity, no CronJob) — needs a custom repo-server. *(not yet wired)*

**F. Install Image Updater + apps** 🖐️ — `kubectl apply platform/image-updater.yaml` then
`apps/grpc-conn-debug/{server,client}.yaml`.

**G. First run** 🖐️ — push the app repo → CodePipeline builds → image in ECR → Image Updater
bumps the tag → ArgoCD deploys.
- ⚠️ Before the first image exists, values are `d-0000000` → Applications stay unhealthy (expected).

## Attention points
1. **03 before 04** (remote-state dependency).
2. **`eks-pod-identity-agent` addon** is required for all ECR access by ArgoCD pods.
3. **ArgoCD ↔ ECR chart auth** — credential helper (identity) or CronJob; either way **verify live**.
4. **Image Updater** `0.12.0` + `write-back-target: helmvalues:` on a multi-source app — **verify live**.
5. ECR repos are **IMMUTABLE** — re-running the same commit pushes no new tag (not an error).

## How the CI/CD works
See the architecture diagram + explanation in `README.md` (this module) and `argo-simple/README.md`.
Short version: push → CodePipeline (Source via connection → S3 → CodeBuild DinD) → 2 images in
ECR → Image Updater polls ECR, commits the new tag to `argo-simple` → ArgoCD pulls the `helm/app`
chart (ECR OCI) + values (git) → syncs to `grpc-debug`.
