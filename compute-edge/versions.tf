# ============================================================
# CAPA: COMPUTE & EDGE
# Ciclo de vida: media | Riesgo: moderado
# Consume outputs de Networking & Core via remote state.
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
    key            = "infra-aws/compute-edge/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}
