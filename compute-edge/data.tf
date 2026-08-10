# Referencia de solo-lectura al estado de la capa Networking & Core.
# Desacopla el ciclo de vida: esta capa nunca declara ni modifica la VPC.
data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = "terraform-state-505231787824"
    key    = "infra-aws/networking-core/terraform.tfstate"
    region = "us-east-2"
  }
}
