variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "default"
}

variable "app_repo_id" {
  description = "GitLab full path (owner/.../repo) the CodeBuild builds from"
  default     = "trongnvv-platform/applications/hello-express"
}
