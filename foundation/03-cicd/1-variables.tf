variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

variable "gitlab_repo_url" {
  description = "GitLab repo CodeBuild builds charts from"
  default     = "https://gitlab.com/trongnvv-platform/helm-chart-template.git"
}
