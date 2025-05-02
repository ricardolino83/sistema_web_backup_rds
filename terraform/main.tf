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

# === NOVOS BLOCOS PARA PERMISSÃO SSM ===

# 1. Obter o ID da Conta AWS atual para construir o ARN do parâmetro
data "aws_caller_identity" "current" {}

# 2. Definir o Documento da Política IAM para ler o parâmetro específico
data "aws_iam_policy_document" "ssm_parameter_read_policy_document" {
  statement {
    sid    = "ReadSecretKeyParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    # ARN do Parâmetro SSM (usando var.project_name para o nome do parâmetro)
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/SECRET_KEY"
    ]
  }
}

# 3. Criar a Política IAM Gerenciada com base no documento acima
resource "aws_iam_policy" "ssm_parameter_read_policy" {
  name        = "${var.project_name}-SSM-Parameter-Read-Policy"
  description = "Permite ler o parâmetro SSM contendo a SECRET_KEY do Django"
  policy      = data.aws_iam_policy_document.ssm_parameter_read_policy_document.json
  tags = {
    Name = "${var.project_name}-SSM-Parameter-Read-Policy"
  }
}

# 4. Anexar a nova Política SSM à Role EC2 existente
resource "aws_iam_role_policy_attachment" "ssm_parameter_read_policy_attach" {
  # Anexa à mesma role usada para acesso S3
  role       = aws_iam_role.ec2_s3_backup_role.name
  policy_arn = aws_iam_policy.ssm_parameter_read_policy.arn
}

# === FIM DOS NOVOS BLOCOS PARA PERMISSÃO SSM ===

# Instance Profile usa a mesma role, que agora terá ambas as políticas anexadas
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
  subnet_id                   = var.subnet_id # Garanta que é uma sub-rede com acesso à internet (NAT se IP público for false)
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false # Confirmado como false

  # Associa o Instance Profile que contém a Role com permissões S3 e SSM
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_backup_profile.name

  # Script User Data (com busca da SECRET_KEY do SSM)
  user_data = <<-EOF
              #!/bin/bash -xe
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

              echo "--- Iniciando User Data Script ---"
              # Variáveis Terraform injetadas no script shell
              REGION="${var.aws_region}"
              TF_PROJECT_NAME="${var.project_name}" # Usando prefixo TF para clareza
              TF_GITHUB_REPO_URL="${var.github_repo_url}"
              TF_PROJECT_DIR_ON_SERVER="${var.project_dir_on_server}"
              TF_DB_PATH_ON_SERVER="${var.db_path_on_server}"

              # Variáveis Shell definidas a partir de outras variáveis
              # Use nomes distintos para variáveis shell se preferir (ex: BASH_PROJECT_NAME)
              PROJECT_NAME="$TF_PROJECT_NAME" # Define a variável shell PROJECT_NAME
              PROJECT_DIR="$TF_PROJECT_DIR_ON_SERVER"
              DB_DIR=$(dirname "$TF_DB_PATH_ON_SERVER")
              VENV_DIR="$PROJECT_DIR/venv"
              STATIC_DIR="$PROJECT_DIR/staticfiles"
              DB_PATH="$TF_DB_PATH_ON_SERVER"
              ENV_FILE="$PROJECT_DIR/.env"
              GUNICORN_SOCKET_FILE="/etc/systemd/system/gunicorn.socket"
              GUNICORN_SERVICE_FILE="/etc/systemd/system/gunicorn.service"

              # Definindo variáveis que usam $PROJECT_NAME (variável shell)
              # CORREÇÃO APLICADA AQUI (Linha ~203 original): Usando $$ para escapar $
              SSM_PARAM_NAME="/$${PROJECT_NAME}/SECRET_KEY"
              # CORREÇÃO APLICADA AQUI (Linha ~212 original): Usando $$ para escapar $
              NGINX_CONF_FILE="/etc/nginx/conf.d/$${PROJECT_NAME}.conf"

              # 1. Atualizar Sistema e Instalar Dependências Base
              # ... (resto do script como estava até a configuração do Nginx) ...

              # 9. Configurar Nginx (Reverse Proxy)
              echo "--- Configurando Nginx ---"
              # ... (outras configurações do Nginx) ...

              rm -f /etc/nginx/conf.d/default.conf # Remove config padrão
              # Cria o arquivo de configuração Nginx (usando a variável shell $NGINX_CONF_FILE)
              cat <<EOT > "$NGINX_CONF_FILE"
              server {
                  listen 80 default_server;
                  server_name $INSTANCE_PRIVATE_IP _; # Escute no IP privado

                  # CORREÇÃO APLICADA AQUI (Linha ~315 original): Usando $$ para escapar $
                  access_log /var/log/nginx/$${PROJECT_NAME}_access.log;
                  # CORREÇÃO APLICADA AQUI (Linha ~316 original): Usando $$ para escapar $
                  error_log /var/log/nginx/$${PROJECT_NAME}_error.log;

                  # Servir arquivos estáticos diretamente pelo Nginx
                  location /static/ {
                      alias $STATIC_DIR/; # Use a variável shell $STATIC_DIR
                      expires 7d; # Cache de arquivos estáticos
                      access_log off; # Opcional: desabilitar log para estáticos
                  }

                  location = /favicon.ico {
                      alias $STATIC_DIR/favicon.ico; # Ajuste o caminho se necessário
                      log_not_found off;
                      access_log off;
                  }

                  # Passar o resto para Gunicorn
                  location / {
                      proxy_set_header Host \$host; # Escapar '$' para Nginx interpretar suas variáveis
                      proxy_set_header X-Real-IP \$remote_addr;
                      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto \$scheme;
                      proxy_pass http://unix:/run/gunicorn.sock; # Aponta para o socket do Gunicorn
                  }
              }
              EOT
              # ... (resto da configuração do Nginx e do script user_data) ...

              echo "--- Fim do User Data Script ---"
              EOF

  # ... (resto do resource aws_instance) ...

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

  # Garante que a role/profile e o SG existem antes de criar a instância
  depends_on = [aws_security_group.app_sg, aws_iam_instance_profile.ec2_s3_backup_profile]
}

# === Outputs ===
# (Mantidos)

output "instance_public_ip" {
  description = "Endereco IP Publico da instancia EC2 criada (vazio se associate_public_ip_address = false)"
  value       = aws_instance.app_server.public_ip
}

output "instance_public_dns" {
  description = "DNS Publico da instancia EC2 criada (vazio se associate_public_ip_address = false)"
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