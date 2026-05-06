# RDS Module - PostgreSQL in private subnets with Multi-AZ

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "db_name" {
  type    = string
  default = "fintech"
}

variable "db_username" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro" # Cost-optimized for dev
}

variable "multi_az" {
  type    = bool
  default = false # true for prod
}

# --- DB Subnet Group ---
resource "aws_db_subnet_group" "main" {
  name       = "fintech-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "fintech-${var.environment}-db-subnet"
    Environment = var.environment
  }
}

# --- Security Group for RDS ---
resource "aws_security_group" "rds" {
  name   = "fintech-${var.environment}-rds-sg"
  vpc_id = var.vpc_id

  # Allow PostgreSQL traffic only from within VPC
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "PostgreSQL from VPC only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fintech-${var.environment}-rds-sg"
  }
}

# --- RDS Instance ---
resource "aws_db_instance" "postgres" {
  identifier = "fintech-${var.environment}-db"

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.multi_az
  storage_type        = "gp3"
  allocated_storage   = 20
  storage_encrypted   = true
  skip_final_snapshot = var.environment != "prod"

  backup_retention_period = var.environment == "prod" ? 7 : 1

  tags = {
    Environment = var.environment
  }
}

# --- Outputs ---
output "db_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "db_host" {
  value = aws_db_instance.postgres.address
}
