#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-us-east-2}"
STATE_BUCKET="terraform-state-505231787824"
ROOT_STATE_KEY="frontend/products-app/terraform.tfstate"
DATA_STATE_KEY="infra-aws/data-persistence/terraform.tfstate"

# Override these when the names are supplied through a tfvars file.
FRONTEND_BUCKET="${TF_VAR_frontend_bucket_name:-products-growshop-bucket-11082026}"
ACCESS_LOGS_BUCKET="${TF_VAR_access_logs_bucket_name:-products-growshop-access-logs-11082026}"

empty_bucket() {
  local bucket="$1"

  echo "Vaciando s3://${bucket}..."
  aws s3 rm "s3://${bucket}" --recursive --region "$REGION" 2>/dev/null || true

  # Also remove versioned objects and delete markers, if versioning was enabled.
  while read -r key version_id; do
    [ -z "$key" ] || aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" --region "$REGION" >/dev/null
  done < <(aws s3api list-object-versions --bucket "$bucket" --region "$REGION" --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null || true)

  while read -r key version_id; do
    [ -z "$key" ] || aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" --region "$REGION" >/dev/null
  done < <(aws s3api list-object-versions --bucket "$bucket" --region "$REGION" --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null || true)
}

echo "=== 1. Vaciando buckets administrados por Terraform ==="
empty_bucket "$FRONTEND_BUCKET"
empty_bucket "$ACCESS_LOGS_BUCKET"

echo "=== 2. Inicializando Terraform ==="
terraform -chdir="$ROOT_DIR" init -input=false

echo "=== 3. Quitando prevent_destroy solo del estado de limpieza ==="
if terraform -chdir="$ROOT_DIR" state list 2>/dev/null | grep -Fxq 'aws_s3_bucket.frontend_bucket'; then
  terraform -chdir="$ROOT_DIR" state rm 'aws_s3_bucket.frontend_bucket'
fi

echo "=== 4. Destruyendo root: Kubernetes, CloudFront, S3, EKS y networking ==="
terraform -chdir="$ROOT_DIR" destroy -auto-approve -input=false -var="aws_region=$REGION"

echo "=== 5. Destruyendo la capa data-persistence si tiene estado ==="
terraform -chdir="$ROOT_DIR/data-persistence" init -input=false
terraform -chdir="$ROOT_DIR/data-persistence" destroy -auto-approve -input=false -var="aws_region=$REGION"

echo "=== 6. Eliminando los buckets de aplicación ==="
aws s3 rb "s3://${FRONTEND_BUCKET}" --force --region "$REGION" 2>/dev/null || true
aws s3 rb "s3://${ACCESS_LOGS_BUCKET}" --force --region "$REGION" 2>/dev/null || true

echo "=== 7. Eliminando solo los estados de estas capas ==="
aws s3 rm "s3://${STATE_BUCKET}/frontend/products-app/" --recursive --region "$REGION" 2>/dev/null || true
aws s3 rm "s3://${STATE_BUCKET}/infra-aws/data-persistence/" --recursive --region "$REGION" 2>/dev/null || true

echo "=== Limpieza terminada. Se conservaron el bucket y los locks de Terraform ==="