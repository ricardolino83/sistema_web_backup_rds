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
resource "aws_security_group" "instance_sg" {
  name        = "instance_sg" # Nome do Security Group
  description = "Permite acesso SSH, HTTP, HTTPS e porta 8000 a partir de um IP especifico"

  # Regras de Entrada (Ingress)
  ingress {
    description      = "SSH from specific IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] # Permite acesso da porta 22 apenas deste IP
  }

  ingress {
    description      = "HTTP from specific IP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] # Permite acesso da porta 80 apenas deste IP
  }

  ingress {
    description      = "HTTPS from specific IP"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] # Permite acesso da porta 443 apenas deste IP
  }

  ingress {
    description      = "Port 8000 from specific IP"
    from_port        = 8000
    to_port          = 8000
    protocol         = "tcp"
    cidr_blocks      = ["10.3.0.138/32"] # Permite acesso da porta 8000 apenas deste IP
  }

  # Regra de Saída (Egress) - Permite todo o tráfego de saída
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1" # Significa todos os protocolos
    cidr_blocks      = ["0.0.0.0/0"] # Permite sair para qualquer lugar
  }

  tags = {
    Name = "instance_sg" # Tag para identificar o Security Group
  }
}

# Cria a instância EC2
resource "aws_instance" "meu_servidor" {
  ami           = "ami-06f3ec245e30a74d3"        # AMI ID que você forneceu (Amazon Linux 2 na sa-east-1)
  instance_type = "t2.micro"                   # Tipo de instância (pode ser alterado)
  key_name      = "Ricardo Lino - Prod"        # Nome do seu Key Pair existente na AWS/sa-east-1
  
  # Associa o Security Group criado acima à instância
  # Usamos o ID do Security Group que o Terraform vai criar
  vpc_security_group_ids = [aws_security_group.instance_sg.id] 

  # Adiciona uma tag para identificar a instância na console da AWS
  tags = {
    Name = "MeuServidorTerraform" # Nome que aparecerá na console da AWS
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