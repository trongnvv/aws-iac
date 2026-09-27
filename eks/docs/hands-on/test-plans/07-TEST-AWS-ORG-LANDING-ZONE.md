# Test — AWS Organizations + Control Tower / Landing Zone

Design-first, unlike the other tests in this plan: what multi-account governance
would look like if this repo's `dev`/`prod` split grew from *two VPCs in one
account* into *two accounts under an Organization*. Read §0–§2 either way; only
run §3 for real on a throwaway account.

> ⚠️ **Do not run §3 on the account this repo's `dev`/`prod` are deployed in.**
> Enabling AWS Organizations is account-wide and not something you tear down like
> an ALB — and this lab's account is running on a **promotional/free credit that
> expires once Organizations is turned on** (this is the reason `enable_*` toggles
> in this repo never assume an Organization exists). If you want the hands-on part,
> do it on a brand-new, separate AWS account created just for this exercise.

## 0. What Control Tower actually provisions
Control Tower orchestrates AWS Organizations + a handful of other services into
one guided setup — it doesn't replace Organizations, it wraps it:
- Your **existing account becomes the Management account** — it stays empty of
  workloads by convention (this is the account this repo currently runs in).
- A **Security OU** with two new dedicated accounts: **Log Archive** (org-wide
  CloudTrail + Config history, nobody logs in day-to-day) and **Audit** (security
  tooling — GuardDuty/Security Hub delegated administration reads from here).
  Names are chosen once at setup and can't change after.
- **Guardrails** — preventive (SCPs — deny an API call outright, e.g. "deny
  leaving the org's home Region") and detective (Config rules — flag, don't
  block). This is the org-wide version of the `enable_network_firewall`/
  `enable_*` toggles this repo already uses per-env, just enforced a level up
  where a single Tofu apply can't override it.
- **Account Factory** — a repeatable way to vend new member accounts (each
  starting with its own baseline: guardrails, logging, network).
- **IAM Identity Center** — one SSO login across every account in the
  Organization (this repo's `admin_principal_arns` on the EKS module already
  expects an SSO permission-set role — Control Tower is where that role would
  actually come from, instead of being hand-typed per env).

## 1. Control Tower vs the Landing Zone Accelerator (LZA)
Two ways to stand this up, not two different end states:
- **Control Tower** — console-guided, AWS-operated; you click through the initial
  landing zone setup, then manage OUs/guardrails/accounts via console, API, or
  Terraform (`aws_organizations_*` resources, or the community
  `aws-samples/aws-control-tower-controls-terraform` pattern) afterward.
- **Landing Zone Accelerator on AWS (LZA)** — a full IaC deployment (a CodePipeline
  that applies dozens of CloudFormation stacks from a config repo) that builds a
  *more opinionated, more automated* landing zone — network baselines, more
  guardrails out of the box, everything as config instead of console clicks.

For a 2-account personal lab, **Control Tower alone is already more than needed**;
LZA is heavier still — it's built for a platform team standing up many accounts
at once, not for turning `dev`/`prod` into 2 accounts. Worth knowing it exists,
not worth running here.

## 2. How this would map onto this repo, specifically
Today: one account, two VPCs (`10.0.0.0/16` dev, `10.1.0.0/16` prod), state keys
`<env>/layer0/<layer>` in one shared S3 bucket (`foundation/00-tf-backend`). The
Organizations-native version of the same idea:
- `dev` and `prod` become **separate member accounts** under a `Workloads` OU —
  the isolation this repo currently gets from state-key-prefix + CIDR separation
  becomes a real account boundary (blast radius: a leaked `prod` credential can't
  touch `dev` at all, vs. today where both share one account's IAM).
- `foundation/00-tf-backend`'s state bucket moves to a dedicated account (or the
  Management account, at small scale) — `docs/DEPLOY.md`'s note *"For separate AWS
  accounts, point each env's `backend.hcl` at that account's bucket"* is exactly
  this move, already anticipated.
- `docs/REVIEW.md`'s "account-level singletons" comment (GuardDuty/CloudTrail/
  Config/SecurityHub, off in `dev`, one-per-account) stops being a convention you
  have to remember — Control Tower's Audit/Log Archive accounts make it structural.
- An SCP could enforce **`enable_network_firewall = true` can't be turned off in
  the prod account** — today that's just a Tofu default someone could edit.

## 3. Hands-on (throwaway account only)
```bash
aws organizations create-organization --feature-set ALL
aws organizations create-organizational-unit \
  --parent-id "$(aws organizations list-roots --query 'Roots[0].Id' --output text)" \
  --name Workloads
```
A minimal preventive guardrail (SCP) — deny leaving the home Region, a common
first policy:
```bash
aws organizations create-policy --name deny-other-regions --type SERVICE_CONTROL_POLICY \
  --description "deny non-ap-southeast-1 actions" --content '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "NotAction": ["iam:*","organizations:*","route53:*","support:*","sts:*"],
    "Resource": "*",
    "Condition": { "StringNotEquals": { "aws:RequestedRegion": "ap-southeast-1" } }
  }]
}'
```
Control Tower's actual landing zone setup (Log Archive/Audit accounts, guardrails,
Identity Center) is console-guided on first run — see AWS's own
[Plan your landing zone](https://docs.aws.amazon.com/controltower/latest/userguide/planning-your-deployment.html)
guide; there's no clean single CLI command for the initial setup, only for
managing it afterward.

## 4. Cleanup
There isn't a `terraform destroy` for this. Undoing an Organization means:
removing every SCP, closing every member account (90-day reclamation window,
can't be undone faster), then `aws organizations delete-organization` from the
Management account once it's the only one left. This is the main reason §3 says
*throwaway account* — treat creating an Organization as a one-way door for
whichever account it runs on.
