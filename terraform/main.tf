# terraform/main.tf

# --- REMOVA os blocos 'data "aws_vpc" "default"' e 'data "aws_subnets" "default"' ---
# Eles não são mais necessários pois usaremos IDs específicos.


# --- Security Group ---
resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-AppSG"
  description = "Permite HTTP, HTTPS, SSH e App(8000) do IP ${var.allowed_ip_cidr}"
  # Usa a VPC especificada na variável:
  vpc_id      = var.target_vpc_id

  # --- REGRAS DE ENTRADA (Ingress) ATUALIZADAS ---
  # Permite tráfego HTTP apenas do IP permitido
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_cidr] # ATUALIZADO
  }

  # Permite tráfego HTTPS apenas do IP permitido
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_cidr] # ATUALIZADO
  }

  # Permite tráfego SSH (Porta 22) apenas do IP permitido
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_cidr] # ATUALIZADO
  }

  # Permite tráfego na porta 8000 (Django Dev) apenas do IP permitido
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip_cidr] # ADICIONADO e ATUALIZADO
  }
  # --- FIM REGRAS DE ENTRADA ---


  # Permite todo tráfego de saída
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-AppSG"
  }
}


# --- IAM Role e Policy para a Instância EC2 ---
# (Nenhuma alteração necessária aqui, mantém como estava)
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-EC2Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      },
    ]
  })
  tags = { Name = "${var.project_name}-EC2Role" }
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "${var.project_name}-S3ListBucketPolicy"
  description = "Permite listar o bucket de backups e obter objetos"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:ListBucket"]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.s3_backup_bucket_name}"
      },
      # Descomente abaixo se precisar ler os objetos .bak
      # {
      #   Action = ["s3:GetObject"]
      #   Effect = "Allow"
      #   Resource = "arn:aws:s3:::${var.s3_backup_bucket_name}/*"
      # }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-EC2Profile"
  role = aws_iam_role.ec2_role.name
}


# --- Instância EC2 ---
# (Data source da AMI não precisa mudar, ele busca na região definida no provider)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  # Usa a Subnet especificada na variável:
  subnet_id = var.target_subnet_id # ATUALIZADO

  # Associa o Security Group criado:
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  # Associa o Perfil IAM criado:
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Chave SSH - Lembre-se de criar/ter a chave 'minha-chave-ssh' na região sa-east-1
  # key_name = "minha-chave-ssh" # SUBSTITUA pelo nome da sua keypair

  # Script user_data atualizado para usar a variável de região
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y python3 python3-pip git nginx
              # Instala SSM Agent usando a região correta
              dnf install -y https://s3.${var.aws_region}.amazonaws.com/amazon-ssm-${var.aws_region}/latest/linux_amd64/amazon-ssm-agent.rpm
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              EOF

  tags = {
    Name = "${var.project_name}-AppServer"
  }
}
