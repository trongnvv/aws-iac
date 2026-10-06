variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

variable "app_repo_id" {
  description = "GitLab full path CodePipeline builds (owner/.../repo)"
  default     = "trongnvv-platform/applications/grpc-conn-debug"
}

# SecretsManager secret holding the GitLab deploy token CI uses to commit the image tag into the
# gitops repo (push model). JSON: {"username":"gitlab+deploy-token-N","password":"gldt-..."} (scope
# read_repository + write_repository). Same secret ESO reads for the ArgoCD repo-argo-simple secret.
# Named under prod/* to match the ESO role's allowed path (eks modules/addon-iam eso_secret_path).
variable "gitlab_token_secret" {
  default = "prod/gitlab-argo-simple-token"
}
