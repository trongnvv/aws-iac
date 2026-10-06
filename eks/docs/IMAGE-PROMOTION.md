# Image promotion (GitOps CD) — decided: CI-push

How a built image reaches dev → stg → prod. **Build once, promote the same digest** (retag), CD by
Argo CD. **Decision: push model (B below) — implemented.** Image Updater (pull) was tried first and
dropped; this doc records why.

## Current wiring (push model)
- **CI commits the tag** — the app `buildspec.yml` (`foundation/04-app-cicd`, `05-hello-express-cicd`),
  after build/retag, writes the image tag into `{env}/*-values.yaml` in `argo-simple` and pushes,
  using a GitLab deploy token from Secrets Manager (`prod/gitlab-argo-simple-token`).
- **CD** = Argo CD `ApplicationSet` (one Application per env) syncing git. No Image Updater.
- **Bootstrap** = root app-of-apps (`argo-simple/bootstrap/root-app.yaml`) syncs `**/appset*.yaml`.
- **prod gate** = the prod Application has no `automated` block → the CI commit shows **OutOfSync**,
  a human clicks **Sync**.

## Why not pull (Image Updater) — the rough edges that killed it
1. Image Updater writes back to git + needs a CR per env/app → `image-updater.yaml` files scattered.
2. CRs shared folders with `values.yaml` → the root app-of-apps had to glob-cherry-pick (fragile).
3. ECR auth for the controller (no native ECR source) → pullsecret/ESO token + opaque "no tags found"
   failures that swallow the real HTTP error. Hours of registry-auth debugging for no payoff.
Push avoids all three: CI already knows the exact tag it produced — just commit it.

## Options considered
| | What | Fixes | Cost |
|---|---|---|---|
| A. Restructure by type | keep Image Updater; split `appsets/` + `image-updaters/` folders | glob only | still pull + its auth pain |
| **B. Push model (CHOSEN)** | drop Image Updater; CI commits the tag; Argo CD syncs | all of the above; git history = deploy history, deterministic | CI needs a gitops write token (deploy token in Secrets Manager); CI↔gitops coupling |
| C. Kargo | purpose-built multi-stage promotion (`Warehouse`→`Freight`→`Stage` + approval gate) | all + a real gate | extra component to run/learn |

## Decision
- **B (CI-push) — implemented.** Fewest moving parts, fits build-once-promote, nothing to debug at
  the registry-auth layer. Good "push vs pull in GitOps, and why" interview talking point.
- **C (Kargo)** stays the purpose-built answer if multi-env promotion with first-class gates is ever
  needed — keep it in mind.

## Credential (one deploy token, two readers)
Secrets Manager `prod/gitlab-argo-simple-token` = GitLab deploy token JSON `{username,password}`
(scopes `read_repository` + `write_repository`):
- **ArgoCD** reads it via ESO → `repo-argo-simple` git repo secret (`02-platform/00-argocd`).
- **CI (CodeBuild)** reads it as `GITLAB_USER`/`GITLAB_TOKEN` env to clone+commit+push.
