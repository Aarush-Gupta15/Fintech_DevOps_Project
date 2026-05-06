# Dev Environment - Single region, minimal resources
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 with DynamoDB locking
  backend "s3" {
    bucket         = "fintech-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-south-1"
}

# --- VPC Module ---
module "vpc" {
  source             = "../../modules/vpc"
  environment        = "dev"
  region             = "ap-south-1"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-south-1a", "ap-south-1b"]
}

# --- EKS Module ---
module "eks" {
  source              = "../../modules/eks"
  environment         = "dev"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = ["t3.medium"]
  desired_capacity    = 2
  min_size            = 1
  max_size            = 3
}

# --- RDS Module ---
module "rds" {
  source             = "../../modules/rds"
  environment        = "dev"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_password        = var.db_password
  instance_class     = "db.t3.micro"
  multi_az           = false # Cost saving for dev
}

variable "db_password" {
  type      = string
  sensitive = true
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "db_endpoint" {
  value = module.rds.db_endpoint
}
