# ============================================================
# SECRETOS BASE (AWS SSM PARAMETER STORE)
#
# Nota: no se definen RDS/S3 aqui porque la persistencia actual
# (MongoDB Atlas) es externa a AWS. Este es el punto de extension
# para futuros aws_db_instance / aws_db_subnet_group / aws_s3_bucket.
# ============================================================

resource "aws_ssm_parameter" "mongo_uri" {
  name      = "/prod/products-service/MONGO_URI"
  type      = "SecureString"
  value     = "placeholder"
  overwrite = false

  lifecycle {
    ignore_changes = [value]
  }
}
