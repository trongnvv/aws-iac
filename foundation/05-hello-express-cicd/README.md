# foundation/05-hello-express-cicd — hello-express CI (CodeBuild → ECR)

One standalone CodeBuild for the GitLab repo `trongnvv-platform/applications/hello-express`:
on `main` it runs **test + scan + build** and pushes `d-<sha>`; on a git tag (`rc-*`/semver) it
**promotes** (retags the same digest). Mode is decided in `buildspec.yml` by the trigger. CD is
ArgoCD + Image Updater, 3 envs (`gitlab argo-simple/apps/hello-express/`).

| File | Resources |
|---|---|
| `2-codebuild.tf` | IAM role + CodeBuild `hello-express-build` (DinD) + webhook (main + tags) |

Reuses the GitLab connection + source credential from `03-cicd` (account-level). ECR repo
`hello-express` is self-provisioned by the buildspec on first build.

## Why standalone CodeBuild (not CodePipeline)
The whole CI — lint, unit/integration tests, SAST, dep scan, build, push — fits in one
`buildspec.yml` with phases; CD is GitOps (ArgoCD), outside the pipeline. There is no multi-stage
orchestration or in-pipeline deploy, so CodePipeline (+ S3 artifact + a second role) would add
overhead with no payoff. This mirrors `03-cicd` (the helm chart pipeline). *(grpc-conn-debug in
`04` still uses CodePipeline — kept as a second, different CI shape.)*

## CI steps (build mode, on main)
`npm ci` → `eslint` (gate) → `node --test` unit+integration (gate) → coverage (non-blocking) →
**SAST (Sonar)** — skipped until `SONAR_HOST_URL`/`SONAR_TOKEN` are set on the project →
`npm audit` dep scan (non-blocking) → `docker build` → push `d-<sha>`. Image scan (Trivy) is
intentionally skipped for now.

## Enable Sonar later
Set `SONAR_HOST_URL` + `SONAR_TOKEN` (SecretsManager) env vars on `hello-express-build`, and
uncomment the `secretsmanager:GetSecretValue` statement in `2-codebuild.tf`. The buildspec runs
the scan automatically once the token is present.
