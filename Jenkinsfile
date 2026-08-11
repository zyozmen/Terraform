pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.6.0'
            // El '--entrypoint=' es CRÍTICO para desactivar el entrypoint por defecto de la imagen de Hashicorp
            args "--entrypoint='' -u 0:0 -v /var/run/docker.sock:/var/run/docker.sock -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        TF_IN_AUTOMATION   = 'true'
    }

    stages {
        stage('Validate AWS Credentials & Terraform') {
            steps {
                sh '''
                    echo "[INFO] Verificando versión de Terraform..."
                    terraform version
                    
                    echo "[INFO] Validando existencia de credenciales AWS en el entorno..."
                    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
                        echo "[ERROR] Las variables AWS_ACCESS_KEY_ID o AWS_SECRET_ACCESS_KEY no están disponibles en este agente."
                        exit 1
                    fi
                    echo "[INFO] Credenciales detectadas correctamente."
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                sh '''
                    echo "[INFO] Inicializando backend remoto en S3..."
                    terraform init -input=false
                '''
            }
        }

        stage('Terraform Validate') {
            steps {
                sh '''
                    echo "[INFO] Validando código de Terraform..."
                    terraform validate
                '''
            }
        }

        stage('Terraform Plan') {
            steps {
                sh '''
                    echo "[INFO] Generando plan de ejecución..."
                    terraform plan -input=false -out=tfplan
                '''
            }
        }

        stage('Approval Gate (Production)') {
            when {
                branch 'main'
            }
            steps {
                script {
                    def userInput = input(
                        id: 'userInput',
                        message: '¿Aprobar despliegue de Infraestructura en AWS?',
                        parameters: [
                            choice(name: 'ACTION', choices: ['Proceed', 'Abort'], description: 'Confirmar aplicación de cambios')
                        ]
                    )
                    if (userInput == 'Abort') {
                        error("Despliegue abortado manualmente.")
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    echo "[INFO] Aplicando cambios en producción..."
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
            echo "[ÉXITO] Infraestructura desplegada/actualizada correctamente."
        }
        failure {
            echo "[ERROR] Falló la ejecución del pipeline de infraestructura."
        }
    }
}