# Prod Environment - Multi-region, HA, auto-scaling
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "fintech-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# Primary region
provider "aws" {
  region = "ap-south-1"
  alias  = "primary"
}

# Secondary region for failover
provider "aws" {
  region = "ap-southeast-1"
  alias  = "secondary"
}

# --- Primary Region Infrastructure ---
module "vpc_primary" {
  source             = "../../modules/vpc"
  environment        = "prod"
  region             = "ap-south-1"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  providers = { aws = aws.primary }
}

module "eks_primary" {
  source              = "../../modules/eks"
  environment         = "prod"
  vpc_id              = module.vpc_primary.vpc_id
  private_subnet_ids  = module.vpc_primary.private_subnet_ids
  public_subnet_ids   = module.vpc_primary.public_subnet_ids
  node_instance_types = ["t3.large"]
  desired_capacity    = 3
  min_size            = 2
  max_size            = 6

  providers = { aws = aws.primary }
}

module "rds_primary" {
  source             = "../../modules/rds"
  environment        = "prod"
  vpc_id             = module.vpc_primary.vpc_id
  private_subnet_ids = module.vpc_primary.private_subnet_ids
  db_password        = var.db_password
  instance_class     = "db.t3.medium"
  multi_az           = true # HA for prod

  providers = { aws = aws.primary }
}

# --- Secondary Region Infrastructure (standby) ---
module "vpc_secondary" {
  source             = "../../modules/vpc"
  environment        = "prod-dr"
  region             = "ap-southeast-1"
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = ["ap-southeast-1a", "ap-southeast-1b"]

  providers = { aws = aws.secondary }
}

module "eks_secondary" {
  source              = "../../modules/eks"
  environment         = "prod-dr"
  vpc_id              = module.vpc_secondary.vpc_id
  private_subnet_ids  = module.vpc_secondary.private_subnet_ids
  public_subnet_ids   = module.vpc_secondary.public_subnet_ids
  node_instance_types = ["t3.large"]
  desired_capacity    = 2
  min_size            = 1
  max_size            = 6

  providers = { aws = aws.secondary }
}

variable "db_password" {
  type      = string
  sensitive = true
}

output "primary_cluster" {
  value = module.eks_primary.cluster_name
}

output "secondary_cluster" {
  value = module.eks_secondary.cluster_name
}
