pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.6.0'
            args '-u 0:0 -v /var/run/docker.sock:/var/run/docker.sock'
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
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID_SECRET', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY_SECRET', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        echo "[INFO] Verificando versión de Terraform..."
                        terraform version
                        
                        echo "[INFO] Validando existencia de credenciales AWS..."
                        if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
                            echo "[ERROR] Las credenciales AWS_ACCESS_KEY_ID o AWS_SECRET_ACCESS_KEY están vacías."
                            exit 1
                        fi
                        echo "[INFO] Credenciales detectadas en el entorno."
                    '''
                }
            }
        }

        stage('Terraform Init') {
            steps {
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID_SECRET', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY_SECRET', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        echo "[INFO] Inicializando backend remoto en S3..."
                        terraform init -input=false
                    '''
                }
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
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID_SECRET', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY_SECRET', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        echo "[INFO] Generando plan de ejecución..."
                        terraform plan -input=false -out=tfplan
                    '''
                }
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
                withCredentials([
                    string(credentialsId: 'AWS_ACCESS_KEY_ID_SECRET', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'AWS_SECRET_ACCESS_KEY_SECRET', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        echo "[INFO] Aplicando cambios en producción..."
                        terraform apply -input=false tfplan
                    '''
                }
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