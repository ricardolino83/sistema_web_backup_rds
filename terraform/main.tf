# Bloco de configuração do Terraform e do provedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # --- Bloco de Configuração do Backend S3 ---
  # Mantido como estava - Certifique-se que o bucket e a tabela DynamoDB existem
  backend "s3" {
    bucket         = "do-not-delete-tfstate-sistemabackup-prod-sa-east-1-7bafd8"
    key            = "sistemabackup/terraform.tfstate" # Pode querer ajustar o path se tiver múltiplos ambientes
    region         = "sa-east-1"
    dynamodb_table = "terraform-locks-RicardoLino-prod"
    encrypt        = true
  }
  # ------------------------------------------
}

# === Provedor AWS ===
provider "aws" {
  region = var.aws_region # Usa a variável definida em variables.tf
}

# === IAM Role, Policy e Instance Profile para EC2 S3 Access ===
# (Usa variáveis definidas em variables.tf)

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
  name               = "${var.project_name}-EC2-S3-Role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json
  tags = {
    Name = "${var.project_name}-EC2-S3-Role"
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
      "arn:aws:s3:::${var.s3_backup_bucket_name}"
    ]
  }
  statement {
    sid    = "ReadWriteDeleteBackupObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_backup_bucket_name}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_backup_policy" {
  name        = "${var.project_name}-S3-Policy"
  description = "Permite acesso ao bucket S3 ${var.s3_backup_bucket_name}"
  policy      = data.aws_iam_policy_document.s3_backup_policy_document.json
  tags = {
    Name = "${var.project_name}-S3-Policy"
  }
}

resource "aws_iam_role_policy_attachment" "s3_backup_policy_attach" {
  role       = aws_iam_role.ec2_s3_backup_role.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn
}

resource "aws_iam_instance_profile" "ec2_s3_backup_profile" {
  name = "${var.project_name}-EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_backup_role.name
  tags = {
    Name = "${var.project_name}-EC2-S3-Profile"
  }
}

# === Security Group ===
# (Usa variáveis definidas em variables.tf)

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Permite acesso SSH, HTTP e HTTPS"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
  }
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr
  }
  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Permite todo tráfego de saída
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-sg"
  }
}

# === Instância EC2 ===
# (Usa variáveis definidas em variables.tf)

resource "aws_instance" "app_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true # Alterado para true

  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_backup_profile.name

  # Script User Data (mantido como na sugestão anterior)
  user_data = <<-EOF
              #!/bin/bash -xe
              # Usar -xe para sair em erro e mostrar comandos executados

              echo "--- Iniciando User Data Script ---"

              # 1. Atualizar Sistema e Instalar Dependências Base
              dnf update -y
              dnf install git python3 python3-pip -y
              dnf install nginx -y
              echo "--- Dependências base instaladas ---"

              # 2. Criar Diretórios
              PROJECT_DIR="${var.project_dir_on_server}"
              DB_DIR=$(dirname "${var.db_path_on_server}")
              VENV_DIR="$PROJECT_DIR/venv"
              STATIC_DIR="$PROJECT_DIR/staticfiles" # Diretório para collectstatic
              DB_PATH="${var.db_path_on_server}"

              mkdir -p $PROJECT_DIR
              mkdir -p $DB_DIR
              mkdir -p $STATIC_DIR
              chown -R ec2-user:ec2-user /opt

              echo "--- Diretórios criados ---"

              # 3. Clonar Repositório
              git clone "${var.github_repo_url}" $PROJECT_DIR
              cd $PROJECT_DIR

              echo "--- Repositório clonado ---"

              # 4. Criar e Ativar Ambiente Virtual & Instalar Dependências Python
              python3 -m venv $VENV_DIR
              source $VENV_DIR/bin/activate
              pip install -r requirements.txt
              pip install gunicorn

              echo "--- Ambiente Python configurado ---"

              # 5. Configurar Django (Variáveis de Ambiente e settings.py)
              echo "AVISO: Configure DEBUG, ALLOWED_HOSTS, SECRET_KEY e DATABASE no settings.py ou via ENV VARS!"

              # 6. Rodar Migrações e Coletar Estáticos
              touch $DB_PATH
              chown ec2-user:ec2-user $DB_PATH
              chown ec2-user:ec2-user $DB_DIR

              python manage.py migrate --noinput
              python manage.py collectstatic --noinput --clear

              echo "--- Migrations e Collectstatic concluídos ---"

              # 7. Configurar Gunicorn (Ex: via systemd)
              echo "AVISO: Configure e inicie o serviço Gunicorn via systemd!"

              # 8. Configurar Nginx (Ex: como reverse proxy)
              echo "AVISO: Configure e inicie o Nginx como reverse proxy!"

              # 9. (Opcional) Configurar Backup do SQLite para S3 via Cron
              echo "AVISO: Configure um cron job para backup do SQLite para S3!"

              echo "--- Fim do User Data Script ---"
              EOF

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "${var.project_name}-Root"
    }
  }

  tags = {
    Name = var.project_name
  }

  # Para garantir que o SG existe antes de criar a instância
  depends_on = [aws_security_group.app_sg]
}

# === Outputs ===
# (Mantidos como estavam, mas usando a nova referência 'app_server')

output "instance_public_ip" {
  description = "Endereco IP Publico da instancia EC2 criada"
  value       = aws_instance.app_server.public_ip
}

output "instance_public_dns" {
  description = "DNS Publico da instancia EC2 criada"
  value       = aws_instance.app_server.public_dns
}

output "instance_private_ip" {
  description = "Endereco IP Privado da instancia EC2 criada"
  value       = aws_instance.app_server.private_ip
}

output "instance_iam_role_name" {
  description = "Nome da IAM Role associada a instancia EC2"
  value       = aws_iam_role.ec2_s3_backup_role.name
}

output "instance_iam_profile_name" {
  description = "Nome do IAM Instance Profile associado a instancia EC2"
  value       = aws_iam_instance_profile.ec2_s3_backup_profile.name
}