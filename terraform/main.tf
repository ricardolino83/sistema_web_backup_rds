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
# MUDANÇA 1: Nome lógico do recurso alterado de "instance_sg" para "meu_servidor_sg"
resource "aws_security_group" "meu_servidor_sg" { 
  # MUDANÇA 2: Nome real do Security Group alterado para algo único
  name        = "meu-servidor-sg" 
  description = "Permite acesso SSH, HTTP, HTTPS e porta 8000 a partir de um IP especifico"

  # Regras de Entrada (Ingress) - Mantidas como estavam
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

  # Regra de Saída (Egress) - Mantida como estava
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" 
    cidr_blocks      = ["0.0.0.0/0"] 
  }

  tags = {
    # MUDANÇA 3: Tag Name atualizada para corresponder ao novo nome
    Name = "meu-servidor-sg" 
  }
}

# Cria a instância EC2
resource "aws_instance" "meu_servidor" {
  ami           = "ami-06f3ec245e30a74d3"      
  instance_type = "t2.micro"                   
  key_name      = "Ricardo Lino - Prod"        
  
  # Associa o Security Group criado acima à instância
  # MUDANÇA 4: Referência atualizada para usar o novo nome lógico do Security Group
  vpc_security_group_ids = [aws_security_group.meu_servidor_sg.id] 

  # Adiciona uma tag para identificar a instância na console da AWS
  tags = {
    Name = "MeuServidorTerraform" 
  }
}

# Define uma saída para mostrar o IP público da instância após criada
output "instance_public_ip" {
  description = "Endereco IP Publico da instancia EC2 criada"
  value       = aws_instance.meu_servidor.public_ip
}

# Define uma saída para mostrar o DNS público da instância após criada
output "instance_public_dns" {
  description = "DNS Publico da instancia EC2 criada"
  value       = aws_instance.meu_servidor.public_dns
}