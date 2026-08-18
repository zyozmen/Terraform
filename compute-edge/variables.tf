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
  default     = "1.35"
  description = "Versión de Kubernetes del cluster EKS. Para realizar un upgrade desde 1.34, AWS exige hacerlo en secuencia compatible (p. ej. 1.34 -> 1.35 -> 1.36). Mantener 1.35 evita el salto no soportado por EKS."
}

variable "vpc_id" {
  type        = string
  description = "ID de la VPC donde se creara el cluster EKS"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs de las subredes privadas para los nodos del cluster"
}
