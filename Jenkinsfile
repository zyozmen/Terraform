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

                    echo "[INFO] Verificando backend S3 del proyecto y evitando fallos si ya existe..."
                    S3_BUCKET="products-app-terraform-state"
                    if aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                        echo "[INFO] El bucket S3 ya existe, se reutiliza: $S3_BUCKET"
                    else
                        echo "[INFO] Creando bucket S3: $S3_BUCKET"
                        if aws s3api create-bucket \
                            --bucket "$S3_BUCKET" \
                            --region "$AWS_DEFAULT_REGION" \
                            --create-bucket-configuration LocationConstraint="$AWS_DEFAULT_REGION" 2>/dev/null; then
                            echo "[INFO] Bucket creado correctamente: $S3_BUCKET"
                        else
                            echo "[WARN] No se pudo crear $S3_BUCKET; puede que ya exista o no sea accesible desde esta cuenta."
                        fi
                    fi

                    echo "[INFO] Verificando recursos AWS clave para no romper el pipeline si ya existen..."
                    if aws ecr describe-repositories --repository-names products-service --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                        echo "[INFO] El repositorio ECR products-service ya existe. Terraform lo reutilizará si está en state; si no, debe importarse."
                    fi

                    if aws eks describe-cluster --name products-cluster --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                        echo "[INFO] El cluster EKS products-cluster ya existe. Terraform lo reutilizará si está en state; si no, debe importarse."
                    fi

                    if aws kms list-aliases --region "$AWS_DEFAULT_REGION" --query "Aliases[?AliasName=='alias/products-cluster'] | length(@)" --output text 2>/dev/null | grep -q '^1$'; then
                        echo "[INFO] El alias KMS alias/products-cluster ya existe."
                    fi

                    echo "[INFO] Preflight completado. El pipeline continuará aunque los recursos ya existan y se manejarán con Terraform o import."
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

        stage('Check EKS Cluster State') {
            steps {
                script {
                    env.EKS_CLUSTER_EXISTS = sh(
                        script: '''
                            if aws eks describe-cluster --name products-cluster --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                                echo "true"
                            else
                                echo "false"
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    if (env.EKS_CLUSTER_EXISTS == 'true') {
                        echo "[INFO] El cluster EKS products-cluster ya existe. No se creará de nuevo; solo se gestionarán cambios reales."
                    } else {
                        echo "[INFO] El cluster EKS products-cluster no existe. Terraform lo creará si el plan lo requiere."
                    }
                }
            }
        }

        stage('Terraform Import Existing AWS Resources') {
            steps {
                sh '''
                    set -e
                    set -o pipefail

                    import_if_missing() {
                        resource_addr="$1"
                        resource_id="$2"
                        resource_label="$3"

                        if terraform state list 2>/dev/null | grep -Fqx "$resource_addr"; then
                            echo "[INFO] $resource_label ya está en Terraform state."
                            return 0
                        fi

                        if [ -z "$resource_id" ]; then
                            echo "[INFO] $resource_label no tiene identificador válido para importar."
                            return 0
                        fi

                        echo "[INFO] Importando $resource_label: $resource_addr -> $resource_id"
                        terraform import -input=false "$resource_addr" "$resource_id"
                        echo "[INFO] Import exitoso para $resource_label."
                    }

                    if aws eks describe-cluster --name products-cluster --region "$AWS_DEFAULT_REGION" >/dev/null 2>&1; then
                        echo "[INFO] El cluster EKS products-cluster existe. Importando los recursos ya creados antes del apply."

                        import_if_missing "module.compute.module.eks.aws_eks_cluster.this[0]" "products-cluster" "cluster EKS products-cluster"

                        if aws logs describe-log-groups \
                            --log-group-name-prefix "/aws/eks/products-cluster" \
                            --region "$AWS_DEFAULT_REGION" \
                            --query "logGroups[?logGroupName=='/aws/eks/products-cluster/cluster'] | length(@)" \
                            --output text 2>/dev/null | grep -q '^1$'; then
                            import_if_missing "module.compute.module.eks.aws_cloudwatch_log_group.this[0]" "/aws/eks/products-cluster/cluster" "log group EKS /aws/eks/products-cluster/cluster"
                        fi

                        if aws kms list-aliases --region "$AWS_DEFAULT_REGION" \
                            --query "Aliases[?AliasName=='alias/eks/products-cluster'] | length(@)" \
                            --output text 2>/dev/null | grep -q '^1$'; then
                            import_if_missing "module.compute.module.eks.module.kms.aws_kms_alias.this[\"cluster\"]" "alias/eks/products-cluster" "alias KMS EKS products-cluster"
                        fi
                    else
                        echo "[INFO] El cluster EKS products-cluster no existe. No se hace import de recursos del módulo EKS."
                    fi

                    echo "[INFO] Estado actual de Terraform luego del import:"
                    terraform state list | sed -n '1,40p'
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
                    terraform plan -refresh=true -input=false -out=tfplan
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

                    if [ "${EKS_CLUSTER_EXISTS}" = "true" ]; then
                        echo "[INFO] El cluster EKS ya existe. Terraform solo aplicará cambios reales y no lo recreará."
                    else
                        echo "[INFO] El cluster EKS no existe; Terraform puede crearlo en esta ejecución."
                    fi

                    echo '[INFO] Aplicando infraestructura con Terraform...'
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