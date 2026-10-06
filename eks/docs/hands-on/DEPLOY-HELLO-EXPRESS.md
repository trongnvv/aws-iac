# Hands-on — hello-express CI/CD (full: test + scan → build once → promote → deploy, 3 env)

Same 3-env build-once-promote-deploy shape as `DEPLOY-GRPC-CONN-DEBUG.md`, but the CI is a
**single standalone CodeBuild** (no CodePipeline) that also runs **test + scan**, and the app is a
**single image** (Node/Express, port 3000). **CI commits the image tag into the gitops repo**
(push model, no Image Updater). The old Argo Rollouts lab in `argo-simple/apps/lab/hello-express`
is a separate demo and is left untouched.

## Flow
```
push main         → CodeBuild: npm ci → lint → test → SAST(sonar) → dep-scan → build → push d-<sha> → commit dev  → DEV
git tag rc-1.1.1  → CodeBuild promote: retag d-<sha> → rc-1.1.1   → commit stg  → STG  (auto-sync)
git tag 1.1.1     → CodeBuild promote: retag → 1.1.1              → commit prod → PROD (manual Sync gate)
```
One `buildspec.yml`, two modes by trigger (tag → promote, else → test+build); its `post_build`
commits the tag into `{env}/values.yaml`. Image scan (Trivy) is skipped for now; SAST (Sonar) is
skipped until `SONAR_HOST_URL`/`SONAR_TOKEN` are set.

## Components
- **CI** — `foundation/05-hello-express-cicd`: one CodeBuild `hello-express-build` (GITLAB source via
  the shared `03-cicd` connection) + webhook on `main` + tags. Node+Docker image, privilegedMode.
  `post_build` commits the tag to the gitops repo with the GitLab deploy token.
- **CD** — `gitlab argo-simple/apps/hello-express/`: `appset.yaml` (ApplicationSet → 3 envs) +
  `{dev,stg,prod}/values.yaml` (image, host `hello-express-<env>.trongnv.space`, port 3000).
  prod = no auto-sync (manual gate).

## Setup
1. Platform up (per the grpc runbook): Argo CD + ESO-minted secrets `repo-ecr-helm` (OCI) and
   `repo-argo-simple` (git, from Secrets Manager `prod/gitlab-argo-simple-token`), Pod Identity agent,
   `03-cicd` connection authorized. Nothing to `kubectl apply` for the repo secrets.
2. ⚙️ `foundation/apply.sh` (applies `05` too — CodeBuild + webhook, with the deploy-token env).
3. 🖐️ push `hello-express` (buildspec.yml) and `argo-simple`.
4. 🖐️ CD config — **nothing per-app**. The root app-of-apps (`bootstrap/root-app.yaml`, applied once
   in the grpc runbook) includes `apps/hello-express/` too (glob `**/appset*.yaml`), so Argo CD syncs
   this app's appset automatically. If the root isn't applied yet: `kubectl apply -f bootstrap/root-app.yaml`.

## Day-to-day (same as grpc)
- dev: push `main` → test+build → `d-<sha>` → CI commits dev → auto-deploy ns dev.
- stg: `git tag rc-1.1.1 && git push --tags` → promote → CI commits stg → auto-deploy ns stg.
- prod: `git tag 1.1.1 && git push --tags` → promote → CI commits prod → ArgoCD OutOfSync → manual Sync (gate).

## Enable SAST (Sonar) later
Create the Sonar server + token, then on the CodeBuild project `hello-express-build` set env vars
`SONAR_HOST_URL` (plaintext) and `SONAR_TOKEN` (SecretsManager) — the buildspec's SAST step turns
on automatically (and grant the role `secretsmanager:GetSecretValue`, commented in `2-codebuild.tf`).

## ⚠️ Verify live
- CodeBuild `standard:7.0` has Node 20 + Docker; `npm ci`/`eslint`/`node --test` pass in CI.
- **CI git-commit** (`buildspec.yml` post_build): deploy-token clone + `sed` tag bump + push to `argo-simple`.
- ApplicationSet templatePatch (prod no-auto) — same caveats as grpc.
- The app repo still has a `.gitlab-ci.yml` driving the **Rollouts lab** (on-prem/Istio) — that CI
  is separate; this AWS CodeBuild runs in parallel (different registry/target).
