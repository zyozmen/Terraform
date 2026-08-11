terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-505231787824"
    key            = "frontend/products-app/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-2"
}

# 1. Red y Seguridad (Grupo de Seguridad para habilitar acceso a Spring Boot y SSH)
resource "aws_security_group" "permitir_trafico" {
  name        = "permitir_servicios"
  description = "Habilitar puertos basicos para funcionamiento de la aplicacion"

  # Puerto para SSH (Tu máquina)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["186.83.108.170/32"]
  }

  # Puerto por defecto de Products-API (Backend)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tráfico de salida permitido
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Servidor EC2 para el Backend de Products-API
resource "aws_instance" "backend_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu Server 22.04 LTS en us-east-2. 
  instance_type = "t3.micro"               

  vpc_security_group_ids = [aws_security_group.permitir_trafico.id]

  tags = {
    Name = "Products-API"
  }
}

# 3. Bucket de S3 para el Frontend (React App estatica)
resource "aws_s3_bucket" "frontend_bucket" {
  bucket        = "products-growshop-bucket-11082026"
  force_destroy = true # IMPORTANTE: Permite que Terraform borre todo el contenido al destruir
}

# Configuracion del Bucket de S3 para alojar sitio web estatico
resource "aws_s3_bucket_website_configuration" "react_site" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Outputs para la consola
output "ip_publica_backend" {
  value       = aws_instance.backend_server.public_ip
  description = "Usa esta IP para subir y correr Products-API en el puerto 8080"
}

output "url_frontend_s3" {
  value       = aws_s3_bucket_website_configuration.react_site.website_endpoint
  description = "Direccion para ver tu aplicacion React desplegada"
}