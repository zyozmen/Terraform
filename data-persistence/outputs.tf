output "mongo_uri_parameter_name" {
  description = "Nombre del parametro SSM que contiene el secreto Mongo URI"
  value       = aws_ssm_parameter.mongo_uri.name
}

output "mongo_uri_parameter_arn" {
  description = "ARN del parametro SSM consumido por la capa Compute & Edge"
  value       = aws_ssm_parameter.mongo_uri.arn
}
