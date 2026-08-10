variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "Region de AWS donde se aprovisiona la capa de datos"
}

variable "mongo_database" {
  type        = string
  default     = "GrowShop"
  description = "Nombre de la base de datos MongoDB Atlas (externa a AWS)"
}
