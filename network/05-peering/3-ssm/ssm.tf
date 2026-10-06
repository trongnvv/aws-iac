# Instance role for Session Manager — lets us `aws ssm start-session` into the test hosts with no SSH
# key and no bastion. Shared by all test EC2s (layer 4-ec2). Name is unique per lab so labs can run
# side by side without IAM name clashes.
resource "aws_iam_role" "ssm" {
  name = "net-lab-peer-ssm"
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
  name = "net-lab-peer-ssm"
  role = aws_iam_role.ssm.name
}
