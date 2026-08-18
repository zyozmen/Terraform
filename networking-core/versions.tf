# ============================================================
# CAPA: NETWORKING & CORE
# Se usa como modulo desde el root para que la ejecucion sea unica.
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
