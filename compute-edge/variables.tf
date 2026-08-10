variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "Region de AWS donde se aprovisiona el computo"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "Tag de la imagen de ECR a desplegar (referencia informativa; el despliegue real lo hace el pipeline de la app via kubectl)"
}

variable "cluster_version" {
  type        = string
  default     = "1.30"
  description = "Version de Kubernetes para el cluster EKS"
}
