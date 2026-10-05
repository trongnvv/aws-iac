# Hands-on — hello-express CI/CD (full: test + scan → build once → promote → deploy, 3 env)

Same 3-env build-once-promote-deploy shape as `DEPLOY-GRPC-CONN-DEBUG.md`, but the CI is a
**single standalone CodeBuild** (no CodePipeline) that also runs **test + scan**, and the app is a
**single image** (Node/Express, port 3000). The old Argo Rollouts lab in `argo-simple/apps/lab/
hello-express` is a separate demo and is left untouched.

## Flow
```
push main         → CodeBuild: npm ci → lint → test → SAST(sonar) → dep-scan → docker build → push d-<sha> → DEV
git tag rc-1.1.1  → CodeBuild promote: retag d-<sha> → rc-1.1.1   → STG  (auto-sync)
git tag 1.1.1     → CodeBuild promote: retag → 1.1.1              → PROD (manual Sync gate)
```
One `buildspec.yml`, two modes by trigger (tag → promote, else → test+build). Image scan (Trivy)
is skipped for now; SAST (Sonar) is skipped until `SONAR_HOST_URL`/`SONAR_TOKEN` are set.

## Components
- **CI** — `foundation/05-hello-express-cicd`: one CodeBuild `hello-express-build` (GITLAB source via
  the shared `03-cicd` connection) + webhook on `main` + tags. Node+Docker image, privilegedMode.
- **CD** — `gitlab argo-simple/apps/hello-express/`: `appset.yaml` (ApplicationSet → 3 envs) +
  `{dev,stg,prod}/values.yaml` (image, host `hello-express-<env>.trongnv.space`, port 3000) +
  `{dev,stg,prod}/image-updater.yaml` (ImageUpdater CR per env). prod = no auto-sync (manual gate).

## Setup
1. Platform already up (per the grpc runbook): Argo CD + Image Updater + ESO OCI repo secret, Pod
   Identity agent, GitLab token secret `repo-argo-simple` (apply `argocd-repo-secret.yaml`), connection authorized.
2. ⚙️ `foundation/apply.sh` (applies `05` too — CodeBuild + webhook).
3. 🖐️ push `hello-express` (buildspec.yml) and `argo-simple`.
4. 🖐️ apply the CD config:
   ```bash
   kubectl apply -f apps/hello-express/appset.yaml
   kubectl apply -f apps/hello-express/dev/image-updater.yaml
   kubectl apply -f apps/hello-express/stg/image-updater.yaml
   kubectl apply -f apps/hello-express/prod/image-updater.yaml
   ```

## Day-to-day (same as grpc)
- dev: push `main` → test+build → `d-<sha>` → auto-deploy ns dev.
- stg: `git tag rc-1.1.1 && git push --tags` → promote → auto-deploy ns stg.
- prod: `git tag 1.1.1 && git push --tags` → promote → ArgoCD OutOfSync → manual Sync (gate).

## Enable SAST (Sonar) later
Create the Sonar server + token, then on the CodeBuild project `hello-express-build` set env vars
`SONAR_HOST_URL` (plaintext) and `SONAR_TOKEN` (SecretsManager) — the buildspec's SAST step turns
on automatically (and grant the role `secretsmanager:GetSecretValue`, commented in `2-codebuild.tf`).

## ⚠️ Verify live
- CodeBuild `standard:7.0` has Node 20 + Docker; `npm ci`/`eslint`/`node --test` pass in CI.
- ImageUpdater CRD + ApplicationSet templatePatch (prod no-auto) — same caveats as grpc.
- The app repo still has a `.gitlab-ci.yml` driving the **Rollouts lab** (on-prem/Istio) — that CI
  is separate; this AWS CodeBuild runs in parallel (different registry/target).
