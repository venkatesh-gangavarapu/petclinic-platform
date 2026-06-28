data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["eu-central-1a", "eu-central-1b"]
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  subnet_ids                = module.vpc.subnet_ids
  cluster_security_group_id = module.vpc.eks_cluster_sg_id
  node_security_group_id    = module.vpc.eks_node_sg_id
}

module "dns" {
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment
  domain_name = "venkatesh-gangavarapu.online"
}

module "secrets" {
  source = "../../modules/secrets"

  project     = var.project
  environment = var.environment
  # openai_api_key defaults to "demo" — genai-service degrades gracefully without a real key
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment
}

# Route 53 A record (alias) pointing dev subdomain to the ALB.
# ALB DNS name and zone ID come from the ingress controller after kubectl apply.
resource "aws_route53_record" "dev_app" {
  zone_id = module.dns.zone_id
  name    = "petclinic-dev.venkatesh-gangavarapu.online"
  type    = "A"

  alias {
    name                   = "k8s-petclini-petclini-00eca135a7-422108278.eu-central-1.elb.amazonaws.com"
    zone_id                = "Z215JYRZR1TBD5"
    evaluate_target_health = true
  }
}

# Allow ALB to reach api-gateway pods on port 8080 (target-type=ip uses pod IPs
# directly — traffic hits the EKS cluster SG, not the custom node SG).
resource "aws_security_group_rule" "node_ingress_alb_8080" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  description              = "HTTP from ALB to api-gateway pods (target-type=ip)"
  security_group_id        = module.eks.cluster_node_security_group_id
  source_security_group_id = module.vpc.alb_sg_id
}

# Allow ALB egress to actual node SG on port 8080 (health checks + traffic).
resource "aws_security_group_rule" "alb_egress_8080_cluster_sg" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  description              = "To api-gateway pods via EKS cluster SG (target-type=ip)"
  security_group_id        = module.vpc.alb_sg_id
  source_security_group_id = module.eks.cluster_node_security_group_id
}

# Allow the EKS-managed node SG (auto-created by EKS, distinct from our custom
# eks-node-sg) to reach RDS on port 3306. EKS attaches this SG to all managed
# node group instances — it is not the same as module.vpc.eks_node_sg_id.
resource "aws_security_group_rule" "rds_ingress_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  description              = "MySQL from EKS cluster-managed node SG"
  security_group_id        = module.vpc.rds_sg_id
  source_security_group_id = module.eks.cluster_node_security_group_id
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids             = module.vpc.subnet_ids
  rds_security_group_id  = module.vpc.rds_sg_id

  # dev-specific overrides
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
}
