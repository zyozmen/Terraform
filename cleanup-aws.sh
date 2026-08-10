#!/usr/bin/env bash
set -e

REGION="us-east-2"
S3_BUCKET="terraform-state-505231787824"
STATE_KEY="products-service/terraform.tfstate"
DYNAMO_TABLE="terraform-locks"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

echo "=== 1. Deteniendo y eliminando Servicios de ECS ==="
aws ecs update-service --region $REGION --cluster products-cluster --service products-api-service --desired-count 0 2>/dev/null || true
aws ecs delete-service --region $REGION --cluster products-cluster --service products-api-service --force 2>/dev/null || true

aws ecs update-service --region $REGION --cluster products-cluster --service products-service --desired-count 0 2>/dev/null || true
aws ecs delete-service --region $REGION --cluster products-cluster --service products-service --force 2>/dev/null || true

echo "=== 2. Eliminando Clúster ECS ==="
aws ecs delete-cluster --region $REGION --cluster products-cluster 2>/dev/null || true

echo "=== 3. Eliminando ALB, Listener y Target Group ==="
ALB_ARN=$(aws elbv2 describe-load-balancers --region $REGION --names "products-api-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)

if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  LISTENER_ARN=$(aws elbv2 describe-listeners --region $REGION --load-balancer-arn "$ALB_ARN" --query "Listeners[0].ListenerArn" --output text 2>/dev/null || true)
  if [ -n "$LISTENER_ARN" ] && [ "$LISTENER_ARN" != "None" ]; then
    echo "Eliminando Listener: $LISTENER_ARN"
    aws elbv2 delete-listener --region $REGION --listener-arn "$LISTENER_ARN" 2>/dev/null || true
  fi

  echo "Eliminando Load Balancer: $ALB_ARN"
  aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn "$ALB_ARN" 2>/dev/null || true
  echo "Esperando que el ALB termine de liberarse..."
  aws elbv2 wait load-balancers-deleted --region $REGION --load-balancer-arns "$ALB_ARN" 2>/dev/null || true
fi

TG_ARN=$(aws elbv2 describe-target-groups --region $REGION --names "products-api-tg" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  echo "Eliminando Target Group: $TG_ARN"
  aws elbv2 delete-target-group --region $REGION --target-group-arn "$TG_ARN" 2>/dev/null || true
fi

echo "=== 4. Eliminando Security Groups (ECS, ALB, Mongo Rules) ==="
ALB_SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=products-api-alb-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
ECS_SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=products-api-ecs-sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)

if [ -n "$ECS_SG_ID" ] && [ "$ECS_SG_ID" != "None" ]; then
  echo "Limpiando reglas de Ingress en Security Group ECS: $ECS_SG_ID"
  # Revocar regla de ingress en la EC2 de Mongo si todavía existiera
  MONGO_SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=ip-permission.group-id,Values=$ECS_SG_ID" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
  if [ -n "$MONGO_SG_ID" ] && [ "$MONGO_SG_ID" != "None" ]; then
    aws ec2 revoke-security-group-ingress --region $REGION --group-id "$MONGO_SG_ID" --protocol tcp --port 27017 --source-group "$ECS_SG_ID" 2>/dev/null || true
  fi

  echo "Eliminando Security Group de ECS..."
  aws ec2 delete-security-group --region $REGION --group-id "$ECS_SG_ID" 2>/dev/null || true
fi

if [ -n "$ALB_SG_ID" ] && [ "$ALB_SG_ID" != "None" ]; then
  echo "Eliminando Security Group del ALB..."
  aws ec2 delete-security-group --region $REGION --group-id "$ALB_SG_ID" 2>/dev/null || true
fi

# Limpieza adicional para SG residuales de pruebas
for EXTRA_SG in "products-app-sg"; do
  EXTRA_SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=$EXTRA_SG" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
  if [ -n "$EXTRA_SG_ID" ] && [ "$EXTRA_SG_ID" != "None" ]; then
    aws ec2 delete-security-group --region $REGION --group-id "$EXTRA_SG_ID" 2>/dev/null || true
  fi
done

echo "=== 5. Eliminando CloudWatch Log Group ==="
aws logs delete-log-group --region $REGION --log-group-name "/ecs/products-service" 2>/dev/null || true

echo "=== 6. Eliminando Roles IAM ==="
for ROLE in "products-api-ecs-execution-role" "products-ecs-task-execution-role"; do
  aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null || true
  aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
done

echo "=== 7. Eliminando Repositorio ECR ==="
aws ecr delete-repository --region $REGION --repository-name "products-service" --force 2>/dev/null || true

echo "=== 8. Destruyendo Estado Remoto Corrupto (S3 y DynamoDB) ==="
aws s3 rm "s3://${S3_BUCKET}/${STATE_KEY}" --region $REGION 2>/dev/null || true
aws dynamodb delete-item --table-name "$DYNAMO_TABLE" --key "{\"LockID\": {\"S\": \"${S3_BUCKET}/${STATE_KEY}-md5\"}}" --region $REGION 2>/dev/null || true
aws dynamodb delete-item --table-name "$DYNAMO_TABLE" --key "{\"LockID\": {\"S\": \"${S3_BUCKET}/${STATE_KEY}\"}}" --region $REGION 2>/dev/null || true

echo "=== Limpieza terminada con éxito. Ya puedes correr el pipeline de Jenkins desde cero ==="