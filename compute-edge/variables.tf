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
  default     = "1.36"
  description = "Version recomendada por Amazon EKS para crear o actualizar el cluster. Se mantiene en la ultima version soportada para evitar desactualizacion y riesgo operativo."
}

variable "vpc_id" {
  type        = string
  description = "ID de la VPC donde se creara el cluster EKS"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs de las subredes privadas para los nodos del cluster"
}
