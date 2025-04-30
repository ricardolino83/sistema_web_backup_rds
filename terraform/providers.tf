# terraform/providers.tf (ou no topo do main.tf)

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use uma versão recente e fixe-a (opcionalmente)
    }
  }

  # --- Backend Remoto (RECOMENDADO para CI/CD e times) ---
  # Descomente e configure após criar o bucket S3 e a tabela DynamoDB manualmente ou via um TF inicial
  # backend "s3" {
  #   bucket         = "seu-bucket-para-tfstate" # SUBSTITUA - Nome único global
  #   key            = "projeto-django-ec2/terraform.tfstate" # Caminho do estado no bucket
  #   region         = "us-east-1" # SUBSTITUA - Região do bucket S3 do estado
  #   dynamodb_table = "terraform-lock-table" # SUBSTITUA - Nome da tabela DynamoDB para lock
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
  # Não precisa configurar access_key/secret_key aqui se estiver usando
  # 'aws configure' localmente ou as Actions com OIDC/Secrets no CI/CD.
}