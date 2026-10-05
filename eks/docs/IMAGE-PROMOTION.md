# Image promotion (GitOps CD) — current state + open concern

How a built image reaches dev → stg → prod. **Build once, promote the same digest** (retag), CD by
Argo CD. This doc records the current wiring and a known rough-edge that is **not yet decided**.

## Current wiring
- **CD** = Argo CD `ApplicationSet` (one Application per env) + **Argo Image Updater** (pull: polls
  ECR, writes the new tag back into `{env}/values.yaml` in the gitops repo `argo-simple`).
- **Bootstrap** = a root app-of-apps (`argo-simple/bootstrap/root-app.yaml`) that syncs every
  `appset*.yaml` + `image-updater.yaml` under `apps/` as siblings in ns `argocd`.
- **prod gate** = the prod Application has no `automated` block → Image Updater commits the tag,
  Argo CD shows **OutOfSync**, a human clicks **Sync**.

## The concern — this feels messy. Three roots:
1. **Image Updater writes back to git + needs a CR per env/app** → `image-updater.yaml` files scatter
   across `apps/<app>/<env>/`.
2. **CRs live in the same folders as `values.yaml`** → the root app-of-apps must **glob-cherry-pick**
   (`{**/appset*.yaml,**/image-updater.yaml}`). Fragile: depends on file names, mixes manifest + values.
3. **The prod gate is a hack** — "disable auto-sync, click Sync" — not a real promotion model.

## Options (cleaner, increasing)
| | What | Fixes | Cost |
|---|---|---|---|
| **A. Restructure by type** | top-level `appsets/` + `image-updaters/` folders; root-app syncs them flat (no glob) | #2 | low; still pull + manual gate |
| **B. Push model** *(leaning)* | drop Image Updater; **CI commits the tag** into `{env}/values.yaml` after build/promote; Argo CD just syncs | #1 + #2; git history = deploy history, deterministic | CI needs gitops write token; CI↔gitops coupling. Gate still manual-sync |
| **C. Kargo** | purpose-built multi-stage promotion: `Warehouse` (discover image) → `Freight` → `Stage` with promotion policy + approval **gate** | #1 + #2 + #3 (a real gate) | extra component to run/learn |

## Decision
- **Not decided.** Leaning **B** for now (fewest moving parts, fits build-once-promote; good
  "push vs pull in GitOps, and why" talking point).
- **C (Kargo)** is the purpose-built answer for multi-env promotion with gates — keep it in mind.
- **A** is cosmetic only (removes the glob), doesn't address the root.

## Gotcha already hit
Regex in `allowTags` inside **double-quoted** YAML needs `\\.` (a single `\.` is an invalid YAML
escape → Argo CD "unknown escape character"). Prefer **single quotes** `'regexp:^[0-9]+\.[0-9]+\.[0-9]+$'`
— single-quoted YAML does no escape processing, so one backslash is correct.
