# Instance role for Session Manager — SSM into the on-prem DNS host and the test hosts (layer 4-ec2),
# no SSH key, no bastion. Owned here (first layer that needs an EC2); 4-ec2 reuses it via remote_state.
# Unique per-lab name so it never collides with other labs' net-lab-ssm role.
resource "aws_iam_role" "ssm" {
  name = "net-lab-r53-ssm"
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
  name = "net-lab-r53-ssm"
  role = aws_iam_role.ssm.name
}
