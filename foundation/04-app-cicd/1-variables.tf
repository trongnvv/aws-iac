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
