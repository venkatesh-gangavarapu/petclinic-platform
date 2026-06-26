locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${local.name_prefix}-vpc"
    Component = "networking"
  }
}

# ── Subnets ───────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                         = "${local.name_prefix}-public-${count.index + 1}"
    Component                                    = "networking"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-igw"
    Component = "networking"
  }
}

# ── Route Table ───────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name      = "${local.name_prefix}-public-rt"
    Component = "networking"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Security Groups ───────────────────────────────────────────────────────────
# All SGs created without inline rules to avoid circular reference issues.
# Rules added separately below via aws_security_group_rule resources.

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-eks-cluster-sg"
    Component = "compute"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-eks-node-sg"
    Component = "compute"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL security group - allows 3306 from EKS nodes only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-rds-sg"
    Component = "database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group - allows HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name      = "${local.name_prefix}-alb-sg"
    Component = "networking"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── EKS Cluster SG rules ─────────────────────────────────────────────────────

resource "aws_security_group_rule" "cluster_ingress_nodes_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.eks_cluster.id
  description              = "API server access from worker nodes"
}

resource "aws_security_group_rule" "cluster_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow all outbound"
}

# ── EKS Node SG rules ────────────────────────────────────────────────────────

resource "aws_security_group_rule" "node_ingress_cluster_all" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_node.id
  description              = "All traffic from EKS control plane"
}

resource "aws_security_group_rule" "node_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_node.id
  description       = "Inter-node communication"
}

resource "aws_security_group_rule" "node_ingress_cluster_kubelet" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_node.id
  description              = "Kubelet API from control plane"
}

resource "aws_security_group_rule" "node_ingress_alb_nodeport" {
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_node.id
  description              = "NodePort services from ALB"
}

resource "aws_security_group_rule" "node_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_node.id
  description       = "Allow all outbound"
}

# ── RDS SG rules ─────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "rds_ingress_nodes_mysql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.rds.id
  description              = "MySQL from EKS worker nodes only"
}

# ── ALB SG rules ─────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
}

resource "aws_security_group_rule" "alb_egress_nodeport" {
  type                     = "egress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.alb.id
  description              = "To NodePort range on worker nodes"
}

resource "aws_security_group_rule" "alb_egress_health_check" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.alb.id
  description              = "Health checks to API Gateway on nodes"
}
