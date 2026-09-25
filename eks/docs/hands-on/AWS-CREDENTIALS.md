# AWS credentials — set up before running `foundation`

`tofu`/`helmfile` need AWS credentials to create anything (`fmt`/`validate` don't).
This guide gets you from "no credentials" to `aws sts get-caller-identity` working
for the `default` profile the repo uses.

> 💸 Applying this stack costs money the moment it runs (EKS control plane $0.10/h +
> NAT + nodes). Do the **Cost & safety** section first, and `teardown.sh` when done.

## 0. What you need
1. **An AWS account.** None yet? Create one at <https://aws.amazon.com/> (needs a
   card + phone). The root email/login is the account owner — don't use it day-to-day.
2. **An identity with permissions** (IAM Identity Center user *or* IAM user).
3. **Credentials on your machine** for the CLI profile `default`.

## 1. Permissions this stack needs
`foundation` creates an S3 bucket, a Route 53 zone, an ACM cert, and a shared ECR. The full `eks` stack also creates VPC, EKS, IAM roles, etc. — broad.

- **Personal lab:** attach the AWS-managed policy **`AdministratorAccess`** to your
  identity. Simplest; fine for an account only you use.
- **Shared / regulated account:** scope down to least privilege (out of scope here).

## 2. Get an identity + credentials — pick ONE

### Option A — IAM Identity Center / SSO (recommended)
Short-lived tokens, no long-lived keys on disk.
1. AWS Console → **IAM Identity Center** → Enable.
2. **Users** → Add user (e.g. `eks-lab`) → set email/password.
3. **Permission sets** → Create → use `AdministratorAccess`.
4. **AWS accounts** → select your account → Assign the user + that permission set.
5. On your machine:
   ```bash
   aws configure sso
   # SSO start URL: https://<your-portal>.awsapps.com/start
   # SSO region: the region Identity Center is in
   # pick the account + role; set CLI default region = ap-southeast-1
   # when asked for a profile name, use:  default
   aws sso login --profile default
   ```

### Option B — IAM user + access keys (simplest, less secure)
Long-lived secret — rotate it, never commit it.
1. Console → **IAM** → **Users** → **Create user** (e.g. `eks-lab`), no console access needed.
2. **Attach policies directly** → `AdministratorAccess`.
3. Open the user → **Security credentials** → **Create access key** → use case
   **Command Line Interface (CLI)** → download the **Access key ID** + **Secret**.
4. Configure the CLI:
   ```bash
   aws configure
   # AWS Access Key ID:     <paste>
   # AWS Secret Access Key: <paste>
   # Default region name:   ap-southeast-1
   # Default output format: json
   ```
   This writes `~/.aws/credentials` (`[default]`) and `~/.aws/config`.

## 3. Verify
```bash
aws sts get-caller-identity        # must print Account + Arn
aws configure list                 # confirm profile + region
```

## 4. How the repo consumes it
- Providers use `profile = var.profile` (default **`default`**) and
  `region = var.region` (default **`ap-southeast-1`**).
- If your profile isn't named `default`:
  `export TF_VAR_profile=<name>` (no code change) or `export AWS_PROFILE=<name>`.
- `foundation/00-tf-backend` uses **local** state and needs creds to create the S3
  state bucket; the rest then use that bucket.

## 5. Run foundation
```bash
cd ~/src/github/trongnvv/aws-iac/foundation
export TF_VAR_domain=yourdomain.com        # your registered domain
# If the Route 53 zone already exists (e.g. Phase-1 lab), import instead of duplicating:
#   (cd 01-dns && tofu init && tofu import aws_route53_zone.main <ZONE_ID>)
./apply.sh                                  # creates state bucket + lock, then zone + ACM
# copy the printed name_servers into your registrar (delegation)
```
Then deploy an env: `cd ../eks && ./scripts/deploy.sh dev`.

## 6. Cost & safety (do this first)
- **Budget alarm:** Console → **Billing → Budgets** → create a small monthly budget
  with an email alert, before you apply anything.
- **MFA:** enable on the root user and on your IAM/SSO user.
- **Least privilege later:** `AdministratorAccess` is for a solo lab only.
- **Never commit secrets:** keep `~/.aws/*` out of git. The repo `.gitignore` already
  excludes `env.sh`, `*.tfvars`, and state files.
- **Tear down:** `./scripts/teardown.sh dev` when finished — the cluster bills hourly.

## 7. Troubleshooting
| Error | Cause / fix |
|---|---|
| `Unable to locate credentials` | `aws configure` not run, or wrong profile → set `AWS_PROFILE`/`TF_VAR_profile` |
| `AccessDenied` / `not authorized` | identity lacks permissions → attach `AdministratorAccess` (lab) |
| `InvalidClientTokenId` | access key deleted/deactivated → create a new one |
| `ExpiredToken` / SSO session expired | `aws sso login --profile default` |
| tofu `NoCredentialProviders` | provider profile name ≠ your profile → `export TF_VAR_profile=<name>` |
