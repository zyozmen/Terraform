# Historial de Configuración, Debugging y Despliegue de Pipeline CI/CD

## 📌 Resumen General
Este documento contiene la secuencia histórica de ajustes, correcciones de errores, instalaciones del sistema y configuraciones requeridas para lograr la ejecución exitosa del pipeline de Jenkins para el microservicio **`products-service`**, empaquetado en Docker y desplegado en AWS ECS Fargate mediante Terraform.

---

## 🛠️ 1. Modificaciones Realizadas al `Jenkinsfile`

### A. Correcciones de Seguridad y Optimización del Build
* **Aislamiento de Credenciales de MongoDB:** Se eliminó la inyección directa de credenciales en el comando `./mvnw package -D...` para evitar su exposición pública en la tabla de procesos del sistema (`ps aux`). Se migraron a la variable de entorno `SPRING_DATA_MONGODB_URI` mediante el bloque `withEnv`.
* **Eliminación de Redundancia de Compilación:** Se removió la fase de empaquetado JAR duplicado en el agente de Jenkins, delegando la construcción del artefacto final exclusivamente al `Dockerfile` multi-stage.

### B. Corrección de Funciones Inexistentes y DSL
* **Eliminación de DSL Inválido:** Se removió la llamada sintácticamente incorrecta `credentialsId()` dentro del bloque `docker.withRegistry`.
* **Manejo Dinámico del Binario de Terraform:** Se configuró la descarga automática y ejecución del binario portátil de Terraform `./terraform` dentro del workspace en caso de no encontrarse instalado en el sistema host.

### C. Estructura Final Sugerida del `Jenkinsfile`
```groovy
pipeline {
    agent any

    environment {
        AWS_REGION     = 'us-east-2'
        REPO_NAME      = 'products-service'
        ECR_ACCOUNT_ID = '505231787824'
        ECR_URL        = "${ECR_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}[.amazonaws.com/$](https://.amazonaws.com/$){REPO_NAME}"
        IMAGE_TAG      = "build-${BUILD_NUMBER}-${GIT_COMMIT.take(7)}"

        APP_NAME             = 'products-api'
        MONGO_CONTAINER_NAME = 'mongo'
        MONGO_PORT           = '27017'
        DB_NAME              = 'GrowShop'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test & Verify') {
            steps {
                withCredentials([usernamePassword(
                        credentialsId: 'MONGO_DB_CREDENTIALS',
                        usernameVariable: 'MONGO_USER',
                        passwordVariable: 'MONGO_PASSWORD'
                )]) {
                    withEnv(["SPRING_DATA_MONGODB_URI=mongodb://${MONGO_USER}:${MONGO_PASSWORD}@${MONGO_CONTAINER_NAME}:${MONGO_PORT}/${DB_NAME}?authSource=admin"]) {
                        sh './mvnw clean test'
                    }
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withCredentials([string(credentialsId: 'SONAR_TOKEN', variable: 'SONAR_TOKEN')]) {
                    withSonarQubeEnv('SonarQube-Server') { 
                        sh "mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.token=${SONAR_TOKEN}"
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "Pipeline abortado debido a fallo en el Quality Gate de SonarQube: ${qg.status}"
                        }
                    }
                }
            }
        }

        stage('AWS ECR Login & Build') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                        docker build -t ${ECR_URL}:${IMAGE_TAG} .
                        docker push ${ECR_URL}:${IMAGE_TAG}
                    """
                }
            }
        }

        stage('Terraform Provision & Deploy') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh """
                        export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                        export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                        export AWS_DEFAULT_REGION=${AWS_REGION}

                        if ! command -v terraform &> /dev/null; then
                            curl -s -O [https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip](https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip)
                            unzip -q -o terraform_1.5.7_linux_amd64.zip
                            chmod +x terraform
                            TF_CMD="./terraform"
                        else
                            TF_CMD="terraform"
                        fi

                        \$TF_CMD init
                        \$TF_CMD apply -auto-approve -var="image_tag=${IMAGE_TAG}"
                    """
                }
            }
        }
    }

    post {
        always {
            sh "docker rmi ${ECR_URL}:${IMAGE_TAG} || true"
            cleanWs()
        }
        failure {
            echo "El pipeline falló en la ejecución. Revisa los logs de los pasos anteriores."
        }
    }
}

# Anexo Técnico: Implementación de Estado Remoto e Importación en Terraform

## 📌 Contexto y Problemática
Posterior a la ejecución exitosa de los scripts de CI/CD, el workspace efímero de Jenkins (`cleanWs()`) eliminaba el archivo local `terraform.tfstate` tras cada ejecución. Esto generaba un fallo recurrente de desincronización (*State Drift*) en las siguientes ejecuciones:

* **Incapacidad de rastrear recursos existentes:** Terraform intentaba crear nuevamente componentes presentes en AWS (`ECR`, `IAM Roles`, `Security Groups`, `CloudWatch Log Groups`), arrojando errores del API de AWS tipo `ResourceAlreadyExistsException`, `EntityAlreadyExists` e `InvalidGroup.Duplicate`.

---

## 🏗️ 1. Creación de Infraestructura para Estado Remoto (AWS CLI)

Para solucionar de raíz la pérdida de estado, se aprovisionó un almacenamiento centralizado y un mecanismo de bloqueo concurrente mediante AWS CLI:

```bash
# 1. Crear Bucket de S3 para almacenar el terraform.tfstate en us-east-2
aws s3api create-bucket \
    --bucket terraform-state-505231787824 \
    --region us-east-2 \
    --create-bucket-configuration LocationConstraint=us-east-2

# 2. Habilitar versionamiento en S3 (Resguardo histórico ante corrupción del estado)
aws s3api put-bucket-versioning \
    --bucket terraform-state-505231787824 \
    --versioning-configuration Status=Enabled

# 3. Crear tabla de DynamoDB para State Locking
aws dynamodb create-table \
    --table-name terraform-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-2

    # Anexo Técnico: Automatización de Infraestructura como Código (IaC) y Estado Remoto en CI/CD

## 📌 Contexto y Problemática Final Resuelta

Durante el despliegue del pipeline de Jenkins para el microservicio de productos, se identificaron dos grandes desafíos de arquitectura IaC:

1. **Efecto "Huevo o la Gallina" con Terraform Backend:** Terraform no podía ejecutar `terraform init` si el bucket de S3 (`terraform-state-505231787824`) o la tabla de DynamoDB (`terraform-locks`) no existían previamente en AWS.
2. **Inconsistencias por State Drift y Parches de Importación:** La combinación de bloques `import` con IDs estáticos y data sources (`data "aws_security_group"`) provocaba fallos recurrentes de duplicación (`InvalidGroup.Duplicate`, `InvalidPermission.Duplicate`) o de recursos inexistentes (`Cannot import non-existent remote object`) tras ejecuciones de limpieza.

---

## 🚀 1. Estrategia de Autoreparación del Backend en Jenkinsfile

Para garantizar un pipeline 100% autónomo e idempotente, se integró una etapa de pre-aprovisionamiento directo mediante AWS CLI en el `Jenkinsfile`. Si la infraestructura del backend no existe (por ejemplo, tras un evento de limpieza total), el propio pipeline la crea antes de invocar `terraform init`.

### Etapas implementadas en el `Jenkinsfile`:

```groovy
stage('Verify & Install Tools') {
    steps {
        sh '''
            mkdir -p .bin
            export PATH="${WORKSPACE}/.bin:${PATH}"

            # Instalación aislada de AWS CLI v2 en el workspace
            if ! command -v aws &> /dev/null; then
                curl -s "[https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip](https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip)" -o "awscliv2.zip"
                unzip -q -o awscliv2.zip
                ./aws/install --bin-dir "${WORKSPACE}/.bin" --install-dir "${WORKSPACE}/.aws-cli" --update
                rm -rf awscliv2.zip aws/
            fi

            # Instalación aislada de Terraform en el workspace
            if ! command -v terraform &> /dev/null; then
                curl -s -O [https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip](https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip)
                unzip -q -o terraform_1.5.7_linux_amd64.zip -d "${WORKSPACE}/.bin/"
                chmod +x "${WORKSPACE}/.bin/terraform"
                rm -f terraform_1.5.7_linux_amd64.zip
            fi
        '''
    }
}

stage('Terraform Provision & Deploy') {
    steps {
        withCredentials([
            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
            string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
            sh '''
                export PATH="${WORKSPACE}/.bin:${PATH}"
                export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                export AWS_DEFAULT_REGION=${AWS_REGION}

                BUCKET_NAME="terraform-state-505231787824"
                DYNAMO_TABLE="terraform-locks"

                # 1. Creación idempotente de Bucket S3
                if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
                    aws s3api create-bucket \
                        --bucket "$BUCKET_NAME" \
                        --region ${AWS_REGION} \
                        --create-bucket-configuration LocationConstraint=${AWS_REGION}
                    
                    aws s3api put-bucket-versioning \
                        --bucket "$BUCKET_NAME" \
                        --versioning-configuration Status=Enabled
                fi

                # 2. Creación idempotente de Tabla DynamoDB para Locks
                if ! aws dynamodb describe-table --table-name "$DYNAMO_TABLE" 2>/dev/null; then
                    aws dynamodb create-table \
                        --table-name "$DYNAMO_TABLE" \
                        --attribute-definitions AttributeName=LockID,AttributeType=S \
                        --key-schema AttributeName=LockID,KeyType=HASH \
                        --billing-mode PAY_PER_REQUEST \
                        --region ${AWS_REGION}

                    aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region ${AWS_REGION}
                fi

                # 3. Inicialización y despliegue
                terraform init
                terraform apply -auto-approve -var="image_tag=${IMAGE_TAG}"
            '''
        }
    }
}