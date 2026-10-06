# Instance role for Session Manager — lets us `aws ssm start-session` into the test hosts with no SSH
# key and no bastion. Created here (the provider's service EC2 is the first host that needs it) and
# reused by the consumer test host in layer 4-ec2 via remote state. Name is unique to this lab.
resource "aws_iam_role" "ssm" {
  name = "net-lab-pl-ssm"
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
  name = "net-lab-pl-ssm"
  role = aws_iam_role.ssm.name
}
