# ============================================================
# ECR REPOSITORY & LIFECYCLE (Registro de imagenes)
# ============================================================

resource "aws_ecr_repository" "products_service" {
  name                 = "products-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "products_service_policy" {
  repository = aws_ecr_repository.products_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Eliminar imagenes sin tag tras 1 dia"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Conservar las ultimas 2 imagenes etiquetadas"
        selection    = { tagStatus = "tagged", tagPrefixList = ["v", "build-", "latest"], countType = "imageCountMoreThan", countNumber = 2 }
        action       = { type = "expire" }
      }
    ]
  })
}

# ============================================================
# CLUSTER DE KUBERNETES (AWS EKS)
#
# Nota SRE: este es el UNICO lugar donde se define el cluster,
# los node groups y sus IAM roles. La aplicacion (repo Products)
# no debe poseer estas definiciones; solo interactua actualizando
# imagen/Deployment/Service dentro del namespace de la app.
# ============================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "products-cluster"
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true
  authentication_mode            = "API"
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Un unico worker Spot para cargas de desarrollo de bajo costo.
  eks_managed_node_groups = {
    micro_node = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      ami_type      = "AL2_x86_64"
      instance_types = ["t3.micro"]
      capacity_type  = "SPOT"

      labels = {
        Environment = "production"
        Workload    = "products-api"
      }
    }
  }

  tags = {
    Environment = "production"
    Terraform   = "true"
  }
}
