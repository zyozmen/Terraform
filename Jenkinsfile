pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.7.5'
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

                    aws --version

                    echo "[INFO] Verificando backend S3 y bloqueo de Terraform..."
                    aws s3api head-bucket --bucket terraform-state-505231787824 --region "$AWS_DEFAULT_REGION" 2>/dev/null || \
                    aws s3api create-bucket \
                        --bucket terraform-state-505231787824 \
                        --region "$AWS_DEFAULT_REGION" \
                        --create-bucket-configuration LocationConstraint="$AWS_DEFAULT_REGION"

                    aws dynamodb describe-table --table-name terraform-locks --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1 || \
                    aws dynamodb create-table \
                        --table-name terraform-locks \
                        --attribute-definitions AttributeName=LockID,AttributeType=S \
                        --key-schema AttributeName=LockID,KeyType=HASH \
                        --billing-mode PAY_PER_REQUEST \
                        --region "$AWS_DEFAULT_REGION"

                    echo "[INFO] Asegurando log group idempotente de EKS..."
                    LOG_GROUP="/aws/eks/products-cluster/cluster"
                    EXISTING_LOG_GROUP=$(aws logs describe-log-groups \
                        --log-group-name-prefix "/aws/eks/products-cluster" \
                        --region "$AWS_DEFAULT_REGION" \
                        --query 'logGroups[?logGroupName==`/aws/eks/products-cluster/cluster`].logGroupName' \
                        --output text || true)

                    if [ -n "$EXISTING_LOG_GROUP" ]; then
                        echo "[INFO] El log group ya existe. Importandolo al estado de Terraform."
                        terraform import 'module.compute.module.eks.aws_cloudwatch_log_group.this[0]' "$LOG_GROUP" || true
                    else
                        echo "[INFO] El log group no existe. Creandolo de forma idempotente."
                        aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_DEFAULT_REGION" || true
                    fi
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                sh '''
                    echo "[INFO] Inicializando backend remoto..."
                    terraform init -input=false -reconfigure
                '''
            }
        }

        stage('Import Existing EKS Resources') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    echo "[INFO] Verificando recursos EKS ya existentes para evitar duplicados..."

                    LOG_GROUP="/aws/eks/products-cluster/cluster"
                    EXISTING_LOG_GROUP=$(aws logs describe-log-groups \
                        --log-group-name-prefix "/aws/eks/products-cluster" \
                        --region "$AWS_DEFAULT_REGION" \
                        --query 'logGroups[?logGroupName==`/aws/eks/products-cluster/cluster`].logGroupName' \
                        --output text || true)

                    if [ -n "$EXISTING_LOG_GROUP" ]; then
                        echo "[INFO] Importando log group existente al state de Terraform..."
                        terraform import 'module.compute.module.eks.aws_cloudwatch_log_group.this[0]' "$LOG_GROUP" || true
                    fi

                    KMS_KEY_ID=$(aws kms list-aliases \
                        --region "$AWS_DEFAULT_REGION" \
                        --query 'Aliases[?AliasName==`alias/eks/products-cluster`].TargetKeyId' \
                        --output text || true)

                    if [ -n "$KMS_KEY_ID" ]; then
                        echo "[INFO] Importando KMS key existente del cluster al state de Terraform..."
                        terraform import 'module.compute.module.eks.module.kms.aws_kms_key.this[0]' "$KMS_KEY_ID" || true
                        terraform import 'module.compute.module.eks.module.kms.aws_kms_alias.this["cluster"]' 'alias/eks/products-cluster' || true
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
                    echo "[INFO] Aplicando infraestructura..."
                    terraform apply -input=false tfplan
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