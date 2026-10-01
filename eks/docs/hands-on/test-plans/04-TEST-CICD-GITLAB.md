# Test — CI/CD, GitLab (runner in-cluster → ECR → ArgoCD)

Same **CD** half as `02-TEST-CICD-AWS-NATIVE.md` (ArgoCD, GitOps pull) — only the **CI**
engine changes, to GitLab CI with a runner living on this cluster. Comparing the two
docs side by side is the point of this pair of tests.

## 0. Prereqs
- A GitLab project (gitlab.com or self-managed) with a Dockerfile app — same
  throwaway app as the AWS-native test works.
- Shared ECR `app` repo (`foundation/02-ecr`).
- `envs/<env>/02-platform/00-argocd` applied, and the same manifests-repo Application from
  `02-TEST-CICD-AWS-NATIVE.md` §4 (or a fresh one pointed at a GitLab manifests repo).

## 1. Register a runner token
GitLab project → **Settings → CI/CD → Runners** → create a project runner, copy the
registration token.

## 2. Install gitlab-runner in-cluster (not a layer — ad hoc for this test)
```bash
helm repo add gitlab https://charts.gitlab.io
kubectl create namespace gitlab-runner

helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --set gitlabUrl=https://gitlab.com/ \
  --set runnerRegistrationToken="$RUNNER_TOKEN" \
  --set runners.executor=kubernetes \
  --set runners.privileged=true   # needed for docker build inside the job pod
```
`runners.executor=kubernetes` means every CI job runs as its own pod on this cluster
— no separate build fleet to manage.

## 3. Give the runner's jobs push access to ECR
Simplest path for a lab: store AWS creds as **masked, protected** GitLab CI/CD
variables (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) scoped to an IAM user that
can only push to the `app` repo. (Production-grade alternative: OIDC federation
between GitLab and IAM — no long-lived keys — but that's a separate exercise, not
needed just to prove the pipeline shape.)

## 4. `.gitlab-ci.yml` in the app repo
```yaml
build:
  image: docker:24
  services: [docker:24-dind]
  variables:
    ACCOUNT: "$AWS_ACCOUNT_ID"
    REGION: ap-southeast-1
  script:
    - apk add --no-cache aws-cli
    - aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
    - docker build -t $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/app:$CI_COMMIT_SHORT_SHA .
    - docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/app:$CI_COMMIT_SHORT_SHA
    # bump the tag in the manifests repo (git clone + sed + commit + push), same as the AWS-native test
```

## 5. Run it end to end
```bash
git commit --allow-empty -m "trigger pipeline" && git push
kubectl -n gitlab-runner get pods -w        # a job pod appears while the pipeline runs
kubectl -n argocd get application app -w    # Synced once the manifest bump lands
kubectl rollout status deploy/app
```

## 6. Compare against the AWS-native test
| | CodeBuild | GitLab CI (in-cluster runner) |
|---|---|---|
| Build compute | AWS-managed, off-cluster | Runs **as pods on this EKS cluster** |
| Trigger | GitLab webhook → CodeBuild (CodeConnections) | GitLab push → runner pod |
| Credentials to ECR | IAM role on the CodeBuild project | Static keys as CI variables (or OIDC) |
| CD | ArgoCD, unchanged | ArgoCD, unchanged |

The CD side being identical is the actual finding: **swapping CI engines doesn't
touch the deploy path** when GitOps owns delivery.

## 7. Cleanup
```bash
helm uninstall gitlab-runner -n gitlab-runner
kubectl delete ns gitlab-runner
kubectl delete application app -n argocd   # if this test used its own Application
```
Remove the CI/CD variables and delete the runner from the GitLab project settings.
