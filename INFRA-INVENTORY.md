# Inventario y Clasificación de Recursos — `infra-aws`

Este documento formaliza la separación conceptual de la infraestructura AWS en tres
capas independientes, cada una con su propio ciclo de vida, nivel de riesgo y
estado remoto de Terraform. El objetivo es desacoplar los recursos persistentes
(red, datos) de los recursos de cómputo/despliegue, que cambian con más frecuencia.

> El stack de cómputo de este proyecto usa **Kubernetes (Amazon EKS)**, no ECS.
> Las filas equivalentes a "ECS Cluster / Task Definitions / ALB" del pedido original
> se mapean a sus contrapartes en EKS (Cluster, Node Groups, Deployment/Service/Ingress).

## Capas

| Capa | Recursos AWS | Frecuencia de cambio | Riesgo | Estado remoto (S3 key) |
|---|---|---|---|---|
| **Networking & Core** | VPC, Internet Gateway, NAT Gateway, Subnets (Public/Private), Route Tables, S3 VPC Endpoint, Security Groups base | Casi nula | Crítico | `infra-aws/networking-core/terraform.tfstate` |
| **Data & Persistence** | Secretos base (SSM Parameter Store). *Pendiente/futuro:* RDS Instance/Cluster, Subnet Groups, S3 Buckets de estado/medios | Muy baja | Crítico | `infra-aws/data-persistence/terraform.tfstate` |
| **Compute & Edge** | ECR Repository, EKS Cluster, EKS Managed Node Groups, IAM Roles (Cluster/Node). *Pendiente/futuro:* AWS Load Balancer Controller (ALB), CloudFront, Route53 | Media | Moderado | `infra-aws/compute-edge/terraform.tfstate` |

Cada capa vive en su propia carpeta bajo [Terraform/](Terraform/) como un root module
independiente (`terraform init`/`apply` por separado). `compute-edge` lee la VPC y las
subredes de `networking-core` mediante `data "terraform_remote_state"` — nunca las
declara ni las modifica.

```
Terraform/
├── networking-core/     # VPC, subnets, NAT, route tables, IGW
├── data-persistence/     # Secretos base (SSM), futuros RDS/S3
└── compute-edge/          # ECR, EKS cluster + node groups (lee red via remote state)
```

## Nota de SRE

La aplicación (Spring Boot, este repo) **no posee** definiciones de EKS Cluster, Node
Groups, IAM Roles de clúster/red, ni Ingress Controller/ALB. Esas definiciones viven
exclusivamente en `Terraform/compute-edge` y `Terraform/networking-core`.

El pipeline de la app ([Jenkinsfile](Jenkinsfile)) solo interactúa con la infraestructura a
nivel de:

1. **Registro de imagen en ECR** (`docker build` + `docker push` al repositorio existente).
2. **Actualización del Deployment/Service** de la app en el clúster ya existente
   (`kubectl apply`/`kubectl set image` sobre [products-api-deployment.yaml](products-api-deployment.yaml),
   [products-api-service.yaml](products-api-service.yaml), [products-api-configmap.yaml](products-api-configmap.yaml)) —
   equivalente al "update de task definition/service" en un stack ECS.

El pipeline de la app ya **no ejecuta** `terraform apply` sobre la red, los datos ni
el clúster; ese ciclo de vida corresponde a los pipelines propios de cada capa de
`infra-aws`.
