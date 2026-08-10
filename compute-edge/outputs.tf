output "cluster_endpoint" {
  description = "Endpoint del Control Plane del cluster de EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Nombre oficial del cluster EKS para Kubeconfig"
  value       = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR consumido por el pipeline de la app"
  value       = aws_ecr_repository.products_service.repository_url
}
