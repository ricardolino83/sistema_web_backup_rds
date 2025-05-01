# Bloco de configuração do Terraform e do provedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # --- Bloco de Configuração do Backend S3 ---
  backend "s3" {
    bucket         = "do-not-delete-tfstate-sistemabackup-prod-sa-east-1-7bafd8"
    key            = "sistemabackup/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "terraform-locks-RicardoLino-prod"
    encrypt        = true
  }
  # ------------------------------------------
}

# Configura o provedor AWS para a região desejada
provider "aws" {
  region = "sa-east-1"
}

# --- IAM Role, Policy e Instance Profile para EC2 ---

data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_s3_backup_role" {
  name               = "SistemaWebBackupRDS-EC2-S3-Role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json
  tags = {
    Name = "SistemaWebBackupRDS-EC2-S3-Role"
  }
}

data "aws_iam_policy_document" "s3_backup_policy_document" {
  statement {
    sid    = "ListBackupBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::mybackuprdscorebank" # ARN do Bucket fornecido
    ]
  }
  statement {
    sid    = "ReadWriteDeleteBackupObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
      # Adicione outras ações S3 se necessário (ex: s3:GetObjectVersion)
    ]
    resources = [
      "arn:aws:s3:::mybackuprdscorebank/*" # Permissão para objetos DENTRO do bucket
    ]
  }
}

resource "aws_iam_policy" "s3_backup_policy" {
  name        = "SistemaWebBackupRDS-S3-Policy"
  description = "Permite acesso ao bucket S3 mybackuprdscorebank"
  policy      = data.aws_iam_policy_document.s3_backup_policy_document.json
  tags = {
    Name = "SistemaWebBackupRDS-S3-Policy"
  }
}

resource "aws_iam_role_policy_attachment" "s3_backup_policy_attach" {
  role       = aws_iam_role.ec2_s3_backup_role.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn
}

resource "aws_iam_instance_profile" "ec2_s3_backup_profile" {
  name = "SistemaWebBackupRDS-EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_backup_role.name
  tags = {
    Name = "SistemaWebBackupRDS-EC2-S3-Profile"
  }
}

# --- Security Group ---

resource "aws_security_group" "meu_servidor_sg" {
  name        = "SistemaWebBackupRDS-sg"
  description = "Permite acesso SSH, HTTP, HTTPS e porta 8000 a partir de um IP especifico"
  vpc_id      = "vpc-01949bdd15953d7ae"

  ingress {
    description = "SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.138/32"]
  }
  ingress {
    description = "HTTP from specific IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.138/32"]
  }
  ingress {
    description = "HTTPS from specific IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.138/32"]
  }
  ingress {
    description = "Port 8000 from specific IP"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.138/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "SistemaWebBackupRDS-sg"
  }
}

# --- Instância EC2 ---

resource "aws_instance" "meu_servidor" {
  # !!! IMPORTANTE: Verifique e atualize para um ID de AMI do Amazon Linux 2023 em sa-east-1 !!!
  ami           = "ami-06f3ec245e30a74d3" # <--- ATUALIZE ESTE ID!
  instance_type = "t2.micro"
  key_name      = "Ricardo Lino - Prod"
  subnet_id     = "subnet-0ac0015f3c048a81d"
  vpc_security_group_ids = [aws_security_group.meu_servidor_sg.id]
  associate_public_ip_address = false

  # NOVO: Associa o Instance Profile criado à instância EC2
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_backup_profile.name

  # NOVO: Script User Data para executar na primeira inicialização
  user_data = <<-EOF
              #!/bin/bash
              # Script para Amazon Linux 2023 (use yum para AL2)
              echo "Executando atualizacoes do sistema..."
              dnf update -y 
              echo "Atualizacoes concluidas."
              # Adicione aqui outros comandos se necessário (instalar python, git, etc.)
              # Exemplo:
              # dnf install python3 python3-pip git -y 
              EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    delete_on_termination = true
    tags = {
      Name = "SistemaWebBackupRDS-Root" # Nome da Tag do Volume atualizado
    }
  }

  tags = {
    Name = "SistemaWebBackupRDS"
  }
}

# --- Outputs ---

output "instance_public_ip" {
  description = "Endereco IP Publico da instancia EC2 criada (depende de 'associate_public_ip_address' e da subnet)"
  value       = aws_instance.meu_servidor.public_ip
}

output "instance_public_dns" {
  description = "DNS Publico da instancia EC2 criada (depende de 'associate_public_ip_address' e da subnet)"
  value       = aws_instance.meu_servidor.public_dns
}

output "instance_private_ip" {
  description = "Endereco IP Privado da instancia EC2 criada"
  value       = aws_instance.meu_servidor.private_ip
}

output "instance_iam_role_name" {
  description = "Nome da IAM Role associada a instancia EC2"
  value       = aws_iam_role.ec2_s3_backup_role.name
}

output "instance_iam_profile_name" {
  description = "Nome do IAM Instance Profile associado a instancia EC2"
  value       = aws_iam_instance_profile.ec2_s3_backup_profile.name
}