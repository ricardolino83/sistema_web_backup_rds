# Bloco de configuração do Terraform e do provedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Você pode ajustar a versão conforme necessário
    }
  }
}

# Configura o provedor AWS para a região desejada
provider "aws" {
  region = "sa-east-1"
}

# Cria um Security Group para a instância EC2
resource "aws_security_group" "meu_servidor_sg" { 
  name        = "meu-servidor-sg" # Nome único para o Security Group na VPC
  description = "Permite acesso SSH, HTTP, HTTPS e porta 8000 a partir de um IP especifico"

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
    protocol         = "-1" # Todos os protocolos
    cidr_blocks      = ["0.0.0.0/0"] # Qualquer destino
  }

  tags = {
    Name = "meu-servidor-sg" 
  }
}

# Cria a instância EC2
resource "aws_instance" "meu_servidor" {
  ami           = "ami-06f3ec245e30a74d3"      # AMI ID (Verificar se ainda é válido/desejado)
  instance_type = "t2.micro"                   # Tipo de instância
  key_name      = "Ricardo Lino - Prod"        # Nome do Key Pair (Deve existir em sa-east-1)
  
  # Associa o Security Group criado acima
  vpc_security_group_ids = [aws_security_group.meu_servidor_sg.id] 

  # Garante que NÃO será atribuído um IP público
  associate_public_ip_address = false 

  # Tag para identificar a instância na AWS
  tags = {
    Name = "SistemaWebBackupRDS" 
  }
}

# --- Outputs ---

# Opcional: Mantido para referência, mas retornará vazio/nulo
output "instance_public_ip" {
  description = "Endereco IP Publico da instancia EC2 criada (sera vazio/nulo pois associate_public_ip_address = false)"
  value       = aws_instance.meu_servidor.public_ip 
}

# Opcional: Mantido para referência, mas retornará vazio/nulo
output "instance_public_dns" {
  description = "DNS Publico da instancia EC2 criada (sera vazio/nulo pois associate_public_ip_address = false)"
  value       = aws_instance.meu_servidor.public_dns 
}

# Recomendado: Output do IP Privado, útil para acesso interno
output "instance_private_ip" {
  description = "Endereco IP Privado da instancia EC2 criada"
  value       = aws_instance.meu_servidor.private_ip
}