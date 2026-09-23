# S3 bucket for Velero backups + the IAM role Velero assumes via Pod Identity
# to write backups and snapshot EBS volumes. All gated by enable_backup.
resource "aws_s3_bucket" "velero" {
  count  = var.enable_backup ? 1 : 0
  bucket = "${var.env}-${var.backup_bucket_name}"
}

resource "aws_s3_bucket_public_access_block" "velero" {
  count                   = var.enable_backup ? 1 : 0
  bucket                  = aws_s3_bucket.velero[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "velero" {
  count = var.enable_backup ? 1 : 0
  name  = "${local.cluster_name}-velero"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "velero" {
  count = var.enable_backup ? 1 : 0
  name  = "velero-backup"
  role  = aws_iam_role.velero[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.velero[0].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.velero[0].arn
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "velero" {
  count           = var.enable_backup ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = var.velero_namespace
  service_account = var.velero_service_account
  role_arn        = aws_iam_role.velero[0].arn
}

output "velero_bucket" {
  value = var.enable_backup ? aws_s3_bucket.velero[0].id : null
}

output "velero_role_arn" {
  value = var.enable_backup ? aws_iam_role.velero[0].arn : null
}
