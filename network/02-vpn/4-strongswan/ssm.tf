# Instance role for Session Manager — lets us `aws ssm start-session` into the strongSwan appliance
# AND the test hosts (5-ec2 reads this profile from remote state) with no SSH key. Created in this
# layer (the first instance layer) so 5-ec2 can reuse it. Name is lab-unique (role names are
# account-global) to avoid colliding with lab 1's net-lab-ssm.
resource "aws_iam_role" "ssm" {
  name = "net-lab-vpn-ssm"
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
  name = "net-lab-vpn-ssm"
  role = aws_iam_role.ssm.name
}
