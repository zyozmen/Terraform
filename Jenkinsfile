pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.15.8'
            args "--entrypoint='' -u 0:0 -v /var/run/docker.sock:/var/run/docker.sock"
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        AWS_DEFAULT_REGION    = 'us-east-2'
        TF_IN_AUTOMATION      = 'true'
        // Inyección global para TODOS los stages del pipeline
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
    }

    stages {
        stage('Validate AWS Credentials & Terraform') {
            steps {
                sh '''
                    echo "[INFO] Verificando versión de Terraform..."
                    terraform version

                    echo "[INFO] Validando existencia de credenciales AWS..."
                    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
                        echo "[ERROR] Las credenciales AWS no fueron inyectadas en el entorno global."
                        exit 1
                    fi
                    echo "[INFO] Credenciales detectadas exitosamente en el entorno."
                '''
            }
        }

        stage('Prepare AWS CLI & Terraform Backend') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    echo "[INFO] Verificando AWS CLI..."
                    if ! command -v aws >/dev/null 2>&1; then
                        echo "[INFO] Instalando AWS CLI desde repositorios de Alpine..."
                        apk add --no-cache aws-cli
                    fi

                    if ! command -v kubectl >/dev/null 2>&1; then
                        echo "[INFO] Instalando kubectl desde repositorios de Alpine..."
                        apk add --no-cache kubectl
                    fi

                    aws --version

                    echo "[INFO] Verificando backend S3 y bloqueo por archivo..."
                    aws s3api head-bucket --bucket terraform-state-505231787824 --region "$AWS_DEFAULT_REGION" 2>/dev/null || \
                    aws s3api create-bucket \
                        --bucket terraform-state-505231787824 \
                        --region "$AWS_DEFAULT_REGION" \
                        --create-bucket-configuration LocationConstraint="$AWS_DEFAULT_REGION"

                '''
            }
        }

        stage('Terraform Init') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    echo "[INFO] Limpiando cache local de providers para evitar inconsistencias de lock..."
                    rm -rf .terraform

                    for attempt in 1 2 3; do
                        echo "[INFO] Intento de inicializacion Terraform $attempt/3..."
                        if terraform init -input=false -reconfigure; then
                            break
                        fi

                        if [ "$attempt" -eq 3 ]; then
                            echo "[ERROR] terraform init falló tras 3 intentos."
                            exit 1
                        fi

                        echo "[WARN] terraform init falló; reintentando en 10 segundos..."
                        sleep 10
                    done
                '''
            }
        }

        stage('Import Existing Resources') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    import_if_exists() {
                        address="$1"
                        resource_id="$2"
                        if terraform state list | grep -Fqx "$address"; then
                            echo "[INFO] $address ya esta en el state."
                            return 0
                        fi

                        echo "[INFO] Importando $address ($resource_id)..."
                        terraform import "$address" "$resource_id"
                    }

                    import_if_bucket_exists() {
                        address="$1"
                        bucket="$2"
                        if aws s3api head-bucket --bucket "$bucket" --region "$AWS_DEFAULT_REGION" 2>/dev/null; then
                            import_if_exists "$address" "$bucket"
                        else
                            echo "[INFO] s3://$bucket no existe; Terraform lo creara."
                        fi
                    }

                    echo "[INFO] Adoptando recursos existentes antes del plan..."

                    import_if_bucket_exists 'aws_s3_bucket.frontend_bucket' "${TF_VAR_frontend_bucket_name:-products-growshop-bucket-11082026}"
                    import_if_bucket_exists 'aws_s3_bucket.access_logs' "${TF_VAR_access_logs_bucket_name:-products-growshop-access-logs-11082026}"

                    if aws eks describe-cluster --name products-cluster --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                        import_if_exists 'module.compute.module.eks.aws_eks_cluster.this[0]' 'products-cluster'

                        aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name products-cluster >/dev/null

                        if kubectl get namespace products >/dev/null 2>&1 && ! terraform state list | grep -Fq 'kubernetes_namespace_v1.products'; then
                            echo "[INFO] Importando namespace products existente..."
                            terraform import 'kubernetes_namespace_v1.products' 'products'
                        fi

                        if kubectl get service backend-service --namespace products >/dev/null 2>&1 && ! terraform state list | grep -Fq 'kubernetes_service_v1.backend'; then
                            echo "[INFO] Importando service backend-service existente..."
                            terraform import 'kubernetes_service_v1.backend' 'products/backend-service'
                        fi
                    else
                        echo "[INFO] El cluster EKS no existe; Terraform lo creara."
                    fi

                    LOG_GROUP="/aws/eks/products-cluster/cluster"
                    EXISTING_LOG_GROUP=$(aws logs describe-log-groups \
                        --log-group-name-prefix "/aws/eks/products-cluster" \
                        --region "$AWS_DEFAULT_REGION" \
                        --query 'logGroups[?logGroupName==`/aws/eks/products-cluster/cluster`].logGroupName' \
                        --output text || true)

                    if [ -n "$EXISTING_LOG_GROUP" ] && ! terraform state list | grep -Fq "module.compute.module.eks.aws_cloudwatch_log_group.this[0]"; then
                        echo "[INFO] Importando log group existente al state de Terraform..."
                        terraform import 'module.compute.module.eks.aws_cloudwatch_log_group.this[0]' "$LOG_GROUP"
                    fi

                    KMS_KEY_ID=$(aws kms list-aliases \
                        --region "$AWS_DEFAULT_REGION" \
                        --query 'Aliases[?AliasName==`alias/eks/products-cluster`].TargetKeyId' \
                        --output text || true)

                    if [ -n "$KMS_KEY_ID" ]; then
                        if ! terraform state list | grep -Fq "module.compute.module.eks.module.kms.aws_kms_key.this[0]"; then
                            echo "[INFO] Importando KMS key existente del cluster al state de Terraform..."
                            terraform import 'module.compute.module.eks.module.kms.aws_kms_key.this[0]' "$KMS_KEY_ID"
                        fi

                        if ! terraform state list | grep -Fq 'module.compute.module.eks.module.kms.aws_kms_alias.this["cluster"]'; then
                            echo "[INFO] Importando alias KMS existente del cluster al state de Terraform..."
                            terraform import 'module.compute.module.eks.module.kms.aws_kms_alias.this["cluster"]' 'alias/eks/products-cluster'
                        fi
                    fi

                '''
            }
        }

        stage('Terraform Validate') {
            steps {
                sh '''
                    echo "[INFO] Validando sintaxis..."
                    terraform validate
                '''
            }
        }

        stage('Terraform Plan') {
            steps {
                sh '''
                    echo "[INFO] Generando plan..."
                    terraform plan -input=false -out=tfplan
                '''
            }
        }

        stage('Approval Gate (Production)') {
            steps {
                script {
                    def userInput = input(
                        id: 'userInput',
                        message: '¿Aprobar despliegue de Infraestructura en AWS?',
                        parameters: [
                            choice(name: 'ACTION', choices: ['Proceed', 'Abort'], description: 'Confirmar cambios')
                        ]
                    )
                    if (userInput == 'Abort') {
                        error("Despliegue abortado por el usuario.")
                    }
                }
            }
        }

        stage('Terraform Apply') {
    steps {
        sh '''
            set -e
            set -o pipefail
            echo '[INFO] Aplicando infraestructura con Terraform...'
            terraform apply -input=false tfplan
        '''
    }
}

        stage('Mostrar API Load Balancer') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    echo "[INFO] Esperando hostname del NLB de Products..."
                        aws eks update-kubeconfig --region "$AWS_DEFAULT_REGION" --name products-cluster >/dev/null

                    NLB_HOSTNAME=""
                    
                    NLB_HOSTNAME=$(terraform output -raw url_products_api)

                    echo "[INFO] NLB_HOSTNAME=$NLB_HOSTNAME"
                    echo "[INFO] PRODUCTS_API_URL=http://$NLB_HOSTNAME"
                    echo "[INFO] API_BASE_URL=http://$NLB_HOSTNAME/api"
                '''
            }
        }
    }

    post {
        always {
            sh 'rm -rf tfplan .terraform/environment'
        }
        success {
            echo "[ÉXITO] Pipeline de infraestructura completado."
        }
        failure {
            echo "[ERROR] Falló la ejecución del pipeline."
        }
    }
}