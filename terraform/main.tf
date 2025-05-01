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
    bucket         = "do-not-delete-tfstate-sistemabackup-prod-sa-east-1-7bafd8" # SEU BUCKET S3
    key            = "sistemabackup/terraform.tfstate" # Caminho/nome do arquivo de estado no bucket
    region         = "sa-east-1"                       # Região DO BUCKET S3
    dynamodb_table = "terraform-locks-RicardoLino-prod" # SUA TABELA DYNAMODB
    encrypt        = true                              # Habilita criptografia do estado no S3
  }
  # ------------------------------------------
}

# Configura o provedor AWS para a região desejada
provider "aws" {
  region = "sa-east-1"
}

# Cria um Security Group na VPC especificada
resource "aws_security_group" "meu_servidor_sg" { 
  name        = "SistemaWebBackupRDS-sg" 
  description = "Permite acesso SSH, HTTP, HTTPS e porta 8000 a partir de um IP especifico"
  
  # Especifica a VPC onde o Security Group será criado
  vpc_id      = "vpc-01949bdd15953d7ae" 

  # Regras de Entrada (Ingress)
  ingress {
    description      = "SSH from specific IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] 
  }

  ingress {
    description      = "HTTP from specific IP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] 
  }

  ingress {
    description      = "HTTPS from specific IP"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] 
  }

  ingress {
    description      = "Port 8000 from specific IP"
    from_port        = 8000
    to_port          = 8000
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] 
  }

  # Regra de Saída (Egress)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" 
    cidr_blocks      = ["0.0.0.0/0"] 
  }

  tags = {
    Name = "SistemaWebBackupRDS-sg" 
  }
}

# Cria a instância EC2 na Subnet especificada dentro da VPC
resource "aws_instance" "meu_servidor" {
  ami           = "ami-06f3ec245e30a74d3"
  instance_type = "t2.micro"
  key_name      = "Ricardo Lino - Prod"
  
  # NOVO: Especifica a Subnet ID onde a instância será lançada
  subnet_id     = "subnet-0ac0015f3c048a81d" 

  # Associa o Security Group criado acima (que está na mesma VPC)
  vpc_security_group_ids = [aws_security_group.meu_servidor_sg.id] 

  # Garante que NÃO será atribuído um IP público (pode depender da config da subnet)
  # Se a subnet for pública e você QUISER um IP público nela, mude para 'true'
  associate_public_ip_address = false 

  # Configurações de Armazenamento
  root_block_device {
    volume_size = 30       # Define o tamanho em GiB
    volume_type = "gp3"    # Define o tipo (gp2, gp3, io1, io2, etc.)
    delete_on_termination = true # true (padrão) = exclui o volume ao terminar a instância
                                 # false = mantém o volume após terminar a instância
    # encrypted = true       # Descomente para habilitar criptografia
    # kms_key_id = "arn:..." # Especifique uma chave KMS se necessário
    tags = {
      Name = "SistemaWebBackupRDS"
    }
  }

  tags = {
    Name = "SistemaWebBackupRDS" 
  }
}

# --- Outputs --- #

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