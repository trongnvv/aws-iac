variable "region" { default = "ap-southeast-1" }
variable "profile" { default = "default" }

# Flip to publish a new version via deploy.sh's rollback demo — unused by the base apply.
variable "fail" {
  default = false
}
variable "version_label" {
  default = "v1"
}
