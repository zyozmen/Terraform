# 1. Bucket S3 para almacenar el archivo JSON del estado
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "mi-terraform-state-unico-12345" # Debe ser globalmente único
  force_destroy = false
}

# Habilitar el control de versiones es OBLIGATORIO para poder recuperar el estado si se corrompe
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. Tabla DynamoDB para el bloqueo de estado (State Locking)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "mi-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID" # Este nombre de atributo es obligatorio para Terraform

  attribute {
    name = "LockID"
    type = "S"
  }
}