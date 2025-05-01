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

# === Variáveis ===
# (É uma boa prática definir variáveis em um arquivo separado 'variables.tf')

variable "aws_region" {
  description = "Região AWS para deploy"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome base para os recursos"
  type        = string
  default     = "SistemaWebBackupRDS"
}

variable "vpc_id" {
  description = "ID da VPC onde os recursos serão criados"
  type        = string
  # Substitua pelo seu VPC ID real ou use um data source para encontrá-lo
  # default     = "vpc-01949bdd15953d7ae"
}

variable "subnet_id" {
  description = "ID da Subnet onde a instância EC2 será criada (deve ser pública se associate_public_ip_address=true)"
  type        = string
  # Substitua pelo seu Subnet ID real ou use um data source
  # default     = "subnet-0ac0015f3c048a81d"
}

variable "ami_id" {
  description = "ID da AMI Amazon Linux 2023 para a região"
  type        = string
  # !!! ENCONTRE E COLOQUE AQUI O ID CORRETO DA AMI AL2023 para sa-east-1 !!!
  # Exemplo (NÃO USE ESTE, É FICTÍCIO): default = "ami-0abcdef1234567890"
}

variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Nome do Key Pair EC2 para acesso SSH"
  type        = string
  default     = "Ricardo Lino - Prod" # Certifique-se que este key pair existe na região
}

variable "s3_backup_bucket_name" {
  description = "Nome do bucket S3 para backups"
  type        = string
  default     = "mybackuprdscorebank" # Certifique-se que este bucket existe
}

variable "allowed_ssh_cidr" {
  description = "Bloco CIDR permitido para acesso SSH (porta 22). Use seu IP/32 ou 0.0.0.0/0 com cuidado."
  type        = list(string)
  default     = ["0.0.0.0/0"] # !! CUIDADO: Aberto para todos. Restrinja se possível !!
}

variable "allowed_http_cidr" {
  description = "Bloco CIDR permitido para acesso HTTP/HTTPS (portas 80, 443)."
  type        = list(string)
  default     = ["0.0.0.0/0"] # Aberto para todos para acesso web
}

variable "github_repo_url" {
  description = "URL do repositório GitHub (use HTTPS ou SSH com chave configurada na instância)"
  type        = string
  # Exemplo: default = "https://github.com/seu-usuario/seu-repo.git"
}

variable "project_dir_on_server" {
  description = "Diretório onde o projeto será clonado no servidor"
  type        = string
  default     = "/opt/sistema_web_backup_rds"
}

variable "db_path_on_server" {
  description = "Caminho completo para o arquivo SQLite no servidor"
  type        = string
  # Colocar fora do diretório do código é mais seguro para deploys
  default     = "/opt/data/sistema_web_backup_rds/db.sqlite3"
}

# === Provedor AWS ===
provider "aws" {
  region = var.aws_region
}

# === IAM Role, Policy e Instance Profile para EC2 S3 Access ===
# (Mantido como estava, mas usando variáveis para nomes)

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

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Permite acesso SSH, HTTP e HTTPS"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr # Controlado por variável
  }
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr # Controlado por variável (provavelmente 0.0.0.0/0)
  }
  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr # Controlado por variável (provavelmente 0.0.0.0/0)
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

resource "aws_instance" "app_server" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false # Definido como true para acesso público inicial

  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_backup_profile.name

    user_data = <<-EOF
              #!/bin/bash -xe
              # Usar -xe para sair em erro e mostrar comandos executados

              echo "--- Iniciando User Data Script ---"

              # 1. Atualizar Sistema e Instalar Dependências Base
              dnf update -y
              dnf install git python3 python3-pip -y
              # Instalar Nginx (opcional, mas recomendado como reverse proxy)
              dnf install nginx -y
              # Instalar AWS CLI (geralmente já vem, mas garante)
              # pip3 install awscli --upgrade

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
              chown -R ec2-user:ec2-user /opt # Dar permissão ao usuário padrão

              echo "--- Diretórios criados ---"

              # 3. Clonar Repositório (ou copiar código de outra forma)
              # CUIDADO: Se o repositório for privado, precisa de credenciais ou chave SSH
              git clone "${var.github_repo_url}" $PROJECT_DIR
              cd $PROJECT_DIR

              echo "--- Repositório clonado ---"

              # 4. Criar e Ativar Ambiente Virtual & Instalar Dependências Python
              python3 -m venv $VENV_DIR
              source $VENV_DIR/bin/activate
              pip install -r requirements.txt
              pip install gunicorn # Instalar Gunicorn para servir a app

              echo "--- Ambiente Python configurado ---"

              # 5. Configurar Django (Variáveis de Ambiente e settings.py)
              # !!! ATENÇÃO: GERENCIAMENTO DE SEGREDOS É CRUCIAL AQUI !!!
              # O ideal é usar SSM Parameter Store ou Secrets Manager.
              # Exemplo simplificado (NÃO RECOMENDADO PARA PRODUÇÃO REAL):
              # Criar um arquivo .env ou exportar variáveis
              # echo "SECRET_KEY='$(openssl rand -hex 32)'" > .env # Gerar uma chave aleatória
              # echo "DEBUG=False" >> .env
              # echo "ALLOWED_HOSTS='*'" >> .env # SEJA MAIS ESPECÍFICO EM PRODUÇÃO!
              # echo "DATABASE_URL='sqlite:///$DB_PATH'" >> .env
              # echo "STATIC_ROOT='$STATIC_DIR'" >> .env
              # (Precisa de uma forma para o Gunicorn/Django lerem esse .env, ex: python-dotenv ou systemd)

              # Ajustes necessários no settings.py de produção:
              # - DEBUG = False
              # - ALLOWED_HOSTS = [ 'seu_ip_publico', 'seu_dominio.com' ]
              # - Configurar DATABASES para usar DATABASE_URL (usar dj-database-url)
              # - Configurar STATIC_ROOT
              echo "AVISO: Configure DEBUG, ALLOWED_HOSTS, SECRET_KEY e DATABASE no settings.py ou via ENV VARS!"

              # 6. Rodar Migrações e Coletar Estáticos
              # Garante que o diretório do DB exista e tenha permissão
              touch $DB_PATH
              chown ec2-user:ec2-user $DB_PATH
              chown ec2-user:ec2-user $DB_DIR

              python manage.py migrate --noinput
              python manage.py collectstatic --noinput --clear

              echo "--- Migrations e Collectstatic concluídos ---"

              # 7. Configurar Gunicorn (Ex: via systemd)
              # Criar /etc/systemd/system/gunicorn.service
              # [Unit] Description=gunicorn daemon ... After=network.target
              # [Service] User=ec2-user Group=ec2-user WorkingDirectory=$PROJECT_DIR EnvironmentFile=/path/to/.env ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind unix:$PROJECT_DIR/gunicorn.sock myproject.wsgi:application Restart=always
              # [Install] WantedBy=multi-user.target
              # systemctl enable gunicorn && systemctl start gunicorn
              echo "AVISO: Configure e inicie o serviço Gunicorn via systemd!"

              # 8. Configurar Nginx (Ex: como reverse proxy)
              # Criar /etc/nginx/conf.d/django.conf (ou sites-available/enabled)
              # server { listen 80; server_name seu_ip_ou_dominio; location = /favicon.ico { access_log off; log_not_found off; } location /static/ { root $STATIC_DIR/..; } location / { include proxy_params; proxy_pass http://unix:$PROJECT_DIR/gunicorn.sock; } }
              # systemctl enable nginx && systemctl start nginx
              echo "AVISO: Configure e inicie o Nginx como reverse proxy!"

              # 9. (Opcional) Configurar Backup do SQLite para S3 via Cron
              # echo "0 2 * * * /usr/bin/aws s3 cp $DB_PATH s3://${var.s3_backup_bucket_name}/backups/db-$(date +\\%Y-\\%m-\\%d-\\%H\\%M\\%S).sqlite3" | crontab -u ec2-user -
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