# foundation/03-cicd — Helm chart pipeline (CodeBuild → ECR)

CodeBuild builds the charts in GitLab `trongnvv-platform/helm-chart-template` and pushes them to
ECR as OCI artifacts (`helm/<chart>`). This module owns the IAM role, the GitLab
connection, the CodeBuild project and its webhook. The chart repo owns only the charts and
the runbook.

| File | Resources |
|---|---|
| `2-codebuild-helm-chart.tf` | IAM role `codebuild-helm-chart` + ECR/logs policy |
| `3-codebuild-project.tf` | CodeConnections connection, source credential, CodeBuild project, webhook, `UseConnection` policy |

ECR repos are not declared here — the pipeline creates `helm/<chart>` on first push.

## Auth model

Two boundaries. "Trust" and "auth" are not the same thing.

**A. GitLab ↔ AWS — authenticated both ways.** CodeConnections holds an OAuth token (from
the one-time authorize). AWS → GitLab (clone, webhook setup) uses that token; GitLab → AWS
(webhook on push) is signed with a secret AWS verifies. Neither direction is open.

**B. CodeBuild → ECR — trust, no secret.** CodeBuild assumes the role via its trust policy
(`codebuild.amazonaws.com` + `sts:AssumeRole`). The permission policy scopes the push to
`helm/*`.

```
authorize once:  human OAuth ──▶ AWS gets a GitLab token (CodeConnections)
on push:         GitLab ──signed webhook──▶ AWS ──clone (token)──▶ GitLab
inside AWS:      CodeBuild ──AssumeRole──▶ Role ──temp creds──▶ ECR (helm/*)
```

### GitLab ↔ AWS — step by step

Two credentials cross this boundary, one per direction: an **OAuth token** (GitLab-issued,
AWS-held) for AWS → GitLab, and a **webhook secret** (AWS-generated, stored both sides) for
GitLab → AWS.

**Phase A — connection (once).**
1. `tofu apply` creates the connection in `PENDING` — no token yet.
2. A human authorizes in the console → redirected to GitLab's consent page → approves the
   AWS OAuth app (scopes: read repo + manage webhooks).
3. GitLab issues an OAuth access token (+ refresh token); CodeConnections stores and
   auto-rotates it. Connection → `AVAILABLE`. AWS now holds a token to the repo.

**Phase B — webhook (apply with the connection `AVAILABLE`).**
4. `aws_codebuild_webhook` makes AWS call the GitLab API *with the token* to create a
   project webhook: URL → an AWS endpoint, plus a secret `S` AWS generates. GitLab stores
   both. (This is why apply.sh creates the connection, pauses to authorize, then applies the
   webhook — see Setup.)

**Phase C — each push.**
5. `push main` → GitLab POSTs the webhook to AWS, carrying secret `S` (`X-Gitlab-Token`).
6. AWS verifies `S` and the ref filter (`refs/heads/main`) → `StartBuild`.
7. CodeBuild assumes its role (internal AWS trust — unrelated to GitLab).
8. CodeBuild clones over HTTPS using the connection's OAuth token (`UseConnection`);
   GitLab validates the token and returns the source.

| Credential | Issued by | Held by | Used for | Verified by |
|---|---|---|---|---|
| OAuth token | **GitLab** | AWS (CodeConnections) | clone source, create webhook | GitLab |
| Webhook secret `S` | **AWS** | AWS + GitLab | sign the webhook payload | AWS |

GitLab is the party that *grants* (you authorize once); AWS holds and auto-rotates that
token to clone and to wire the webhook. No PAT, no OIDC — all inside the connection.

## Standalone vs CodePipeline

Both read GitLab through the same CodeConnections connection. What differs is who holds it
and how many roles are in play.

**Standalone (chosen).** The webhook hits the CodeBuild project; CodeBuild clones via the
connection and pushes. One role.

```
GitLab ──signed webhook──▶ CodeBuild ──clone (UseConnection)──▶ CodeBuild ──AssumeRole──▶ ECR
```

Role `codebuild-helm-chart` needs `codeconnections:UseConnection` (clone) **+** ECR push.

**CodePipeline.** The webhook hits the pipeline; its Source stage clones via the connection
into an S3 artifact store, then starts CodeBuild on that artifact. Two roles + a bucket.

```
GitLab ──webhook──▶ CodePipeline (Source: UseConnection → S3) ──StartBuild──▶ CodeBuild ──▶ ECR
```

- Pipeline role: `UseConnection` + S3 read/write + `codebuild:StartBuild`.
- CodeBuild role: S3 read + ECR push (it no longer talks to GitLab — source comes from S3).

| | Standalone | CodePipeline |
|---|---|---|
| Holds the connection | CodeBuild | CodePipeline (Source stage) |
| Clones GitLab | CodeBuild | CodePipeline → S3 |
| Roles | **1** | **2** |
| Artifact store | none | **S3 bucket (required)** |
| Webhook target | CodeBuild project | CodePipeline |

One build step needs no orchestration, so standalone — no second role, no bucket.

## Decisions

- **CodeConnections, not a PAT** — AWS owns the token; nothing to store or rotate.
- **IAM role, not static keys or OIDC** — CodeBuild runs inside AWS, so it uses its own
  identity for short-lived creds. OIDC is only for CI *outside* AWS (e.g. a GitLab runner).
- **ECR repos self-provisioned** — `buildspec.yml` creates `helm/<chart>`; adding a chart
  needs no change here.
- **Scoped to `helm/*`** — the role cannot touch the shared image repos in `02-ecr`.

## Setup

`foundation/apply.sh` does it in one run. The GitLab webhook can only register once the
connection is authorized, so the script creates the connection first (`-target`), then pauses:

1. `./apply.sh` runs, then stops at the authorize prompt.
2. Authorize the GitLab connection in the console (the only manual step).
3. Press ENTER — the script applies the rest (project, webhook) and finishes.

Full runbook: the chart repo's README.
