# ============================================================
# CAPA: COMPUTE & EDGE
# Se usa como modulo desde el root, por lo que no define backend
# ni consumo de estados remotos separados.
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
