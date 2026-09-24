# modules

Reusable OpenTofu building blocks. Each is pure — inputs → resources → outputs, with
**no backend or provider config** (those live in the env roots `envs/<env>/<layer>/`).

| Module | What | Key outputs |
|---|---|---|
| `network` | VPC, subnets (cidrsubnet-derived), NAT, endpoints, secondary CIDR, egress firewall | vpc_id, app_subnet_ids, nat_public_ips |
| `eks` | cluster, managed add-ons, Access Entries, bootstrap node group | cluster_name, oidc_provider_arn, node_security_group_id |
| `karpenter-infra` | node IAM role, instance profile, SQS interruption queue | karpenter_queue_name, karpenter_node_iam_role_name |
| `addon-iam` | Pod Identity roles: LBC, ESO, external-dns, KEDA, cert-manager, kubecost | *_role_arn |
| `ecr` | private registry + image scanning | repository_urls |
| `security-baseline` | GuardDuty, CloudTrail, Config, Security Hub (account-level singletons) | — |
| `observability-aws` | Amazon Managed Prometheus workspace + IAM | amp_workspace_arn, amp_remote_write_url |
| `backup-aws` | Velero S3 bucket + IAM | velero_bucket, velero_role_arn |
| `waf` | regional web ACL for the ALB | web_acl_arn |

**Multi-env safety:** global-unique names are prefixed with the `env` input and
`cluster_name` is per env, so two environments in one account never collide. Every
module is called from `envs/<env>/<NN-layer>/main.tf`, which supplies its backend,
provider, upstream `terraform_remote_state`, and this env's values.
