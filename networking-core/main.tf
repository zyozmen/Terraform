# ============================================================
# VPC, SUBREDES MULTI-AZ, NAT GATEWAY
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name                                      = "vpc-products-prod"
    Environment                               = "production"
    "kubernetes.io/cluster/products-cluster"  = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-products-prod"
  }
}

# Subredes Publicas (Con tags requeridos por Kubernetes Ingress / ALB)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true

  tags = {
    Name                                     = "subnet-public-1a"
    "kubernetes.io/cluster/products-cluster" = "shared"
    "kubernetes.io/role/elb"                 = "1"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name                                     = "subnet-public-1b"
    "kubernetes.io/cluster/products-cluster" = "shared"
    "kubernetes.io/role/elb"                 = "1"
  }
}

# Subredes Privadas (Para Nodos de K8s / Pods)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name                                     = "subnet-private-1a"
    "kubernetes.io/cluster/products-cluster" = "shared"
    "kubernetes.io/role/internal-elb"        = "1"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-2b"

  tags = {
    Name                                     = "subnet-private-1b"
    "kubernetes.io/cluster/products-cluster" = "shared"
    "kubernetes.io/role/internal-elb"        = "1"
  }
}

# Elastic IP & NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "eip-nat-gateway-prod" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags       = { Name = "nat-gateway-prod" }
  depends_on = [aws_internet_gateway.igw]
}

# Tablas de Enrutamiento
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "rt-public-prod" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "rt-private-prod" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# S3 Gateway Endpoint (Ahorro de Costos)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "vpce-s3-gateway-prod" }
}
