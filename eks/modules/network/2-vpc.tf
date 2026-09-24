# Subnet CIDRs derived from vpc_cidr so a whole env shifts to a non-overlapping
# range by changing one knob. Layout (per AZ): public /20, app /20, isolated /24.
locals {
  public_cidrs   = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  app_cidrs      = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, i + 3)]
  isolated_cidrs = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 96)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# Public tier: ALB + NAT live here. elb tag = ALB subnet discovery.
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "public-${var.azs[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# App tier: EKS nodes/pods, egress via NAT.
# internal-elb = internal ALB discovery; karpenter.sh/discovery = Karpenter subnet discovery.
resource "aws_subnet" "app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name                              = "app-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

# Isolated tier: DBs/caches, no internet route at all (see routes.tf).
resource "aws_subnet" "isolated" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.isolated_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "isolated-${var.azs[count.index]}" }
}
