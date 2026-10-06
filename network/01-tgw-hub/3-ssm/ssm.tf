# Instance role for Session Manager — lets us `aws ssm start-session` into the test hosts with no SSH
# key and no bastion. Shared by all test EC2s (layer 4-ec2).
resource "aws_iam_role" "ssm" {
  name = "net-lab-ssm"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "net-lab-ssm"
  role = aws_iam_role.ssm.name
}
