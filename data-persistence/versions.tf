# ============================================================
# CAPA: DATA & PERSISTENCE
# Ciclo de vida: muy baja | Riesgo: critico
# Estado remoto propio, independiente de Networking y Compute.
# ============================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "products-api-terraform-state"
    key          = "infra-aws/data-persistence/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}
