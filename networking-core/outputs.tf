output "vpc_id" {
  description = "ID de la VPC consumido por las capas Data & Persistence y Compute & Edge"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Subredes publicas para recursos de borde (ALB/NLB, NAT)"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "Subredes privadas para Compute (nodos EKS) y Data (RDS Subnet Groups)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

output "nat_gateway_public_ip" {
  description = "IP PUBLICA FIJA para agregar a la Whitelist de MongoDB Atlas"
  value       = aws_eip.nat.public_ip
}
