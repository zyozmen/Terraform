pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:1.6.0'
            // Se pasan credenciales de AWS y montajes necesarios
            args '-u 0:0 -v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds() // Evita race conditions sobre el estado de Terraform
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        // Credenciales configuradas en Jenkins (Manage Jenkins -> Credentials)
        AWS_CREDENTIALS = credentials('aws-credentials-id')
        AWS_ACCESS_KEY_ID     = "${AWS_ACCESS_KEY_ID}"
        AWS_SECRET_ACCESS_KEY = "${AWS_SECRET_ACCESS_KEY}"
        AWS_DEFAULT_REGION    = 'us-east-2'
        TF_IN_AUTOMATION      = 'true'
    }

    stages {
        stage('Validate Environment') {
            steps {
                sh '''
                    echo "[INFO] Verificando versión de herramientas..."
                    terraform version
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                // El backend remoto garantiza que la primera vez inicialice y las siguientes re-use el estado
                sh '''
                    echo "[INFO] Inicializando backend remoto..."
                    terraform init -input=false
                '''
            }
        }

        stage('Terraform Validate & Lint') {
            steps {
                sh '''
                    echo "[INFO] Validando sintaxis de código..."
                    terraform validate
                '''
            }
        }

        stage('Terraform Plan') {
            steps {
                // Genera un plan ejecutable y lo guarda en un archivo binario para garantizar idempotencia
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
                // Pausa el pipeline esperando confirmación manual antes de modificar producción
                script {
                    def userInput = input(
                        id: 'userInput',
                        message: '¿Aprobar cambios de Infraestructura en AWS?',
                        parameters: [
                            choice(name: 'ACTION', choices: ['Proceed', 'Abort'], description: 'Confirmar despliegue')
                        ]
                    )
                    if (userInput == 'Abort') {
                        error("Despliegue abortado por el usuario.")
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                // Aplica ÚNICAMENTE el plan previamente calculado
                sh '''
                    echo "[INFO] Aplicando cambios en infraestructura..."
                    terraform apply -input=false tfplan
                '''
            }
        }
    }

    post {
        always {
            // Limpieza de artefactos locales para evitar fuga de datos sensibles en la máquina host
            sh 'rm -rf tfplan .terraform/environment'
        }
        success {
            echo "[ÉXITO] Infraestructura actualizada correctamente."
        }
        failure {
            echo "[ERROR] Falló la ejecución de Terraform. Revisa los logs."
        }
    }
}