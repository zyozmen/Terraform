# ============================================================
# CAPA: NETWORKING & CORE
# Ciclo de vida: casi nulo | Riesgo: critico
# Estado remoto propio -> desacopla el ciclo de vida de las
# capas de Data & Persistence y Compute & Edge.
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-505231787824"
    key            = "infra-aws/networking-core/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}
