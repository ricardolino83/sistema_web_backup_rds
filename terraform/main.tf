# main.tf

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
    bucket         = "do-not-delete-tfstate-sistemabackup-prod-sa-east-1-7bafd8" # Certifique-se que o bucket existe
    key            = "sistemabackup/terraform.tfstate"
    region         = "sa-east-1"                                                  # Deve corresponder à var.aws_region
    dynamodb_table = "terraform-locks-RicardoLino-prod"                           # Certifique-se que a tabela existe
    encrypt        = true
  }
  # ------------------------------------------
}

# === Provedor AWS ===
provider "aws" {
  region = var.aws_region # Usa a variável definida em variables.tf
}

# === IAM Role, Policy e Instance Profile para EC2 S3 Access ===
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

# === Blocos para Permissão SSM ===
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ssm_parameter_read_policy_document" {
  statement {
    sid    = "ReadSecretKeyParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      # Atenção: Garanta que o nome do parâmetro aqui corresponde EXATAMENTE ao criado no SSM
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/SECRET_KEY"
    ]
  }
}

resource "aws_iam_policy" "ssm_parameter_read_policy" {
  name        = "${var.project_name}-SSM-Parameter-Read-Policy"
  description = "Permite ler o parâmetro SSM SECRET_KEY do Django"
  policy      = data.aws_iam_policy_document.ssm_parameter_read_policy_document.json
  tags = {
    Name = "${var.project_name}-SSM-Parameter-Read-Policy"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_read_policy_attach" {
  role       = aws_iam_role.ec2_s3_backup_role.name
  policy_arn = aws_iam_policy.ssm_parameter_read_policy.arn
}
# === Fim Blocos SSM ===

# === Instance Profile ===
resource "aws_iam_instance_profile" "ec2_s3_backup_profile" {
  name = "${var.project_name}-EC2-S3-Profile"
  role = aws_iam_role.ec2_s3_backup_role.name # A role agora tem ambas as policies (S3 e SSM)
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
    cidr_blocks = var.allowed_http_cidr # Ajustar se necessário
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
  associate_public_ip_address = false # Sem IP público direto

  iam_instance_profile = aws_iam_instance_profile.ec2_s3_backup_profile.name

  user_data = <<-EOF
              #!/bin/bash -xe
              # Log para /var/log/user-data.log E console
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

              echo "--- Iniciando User Data Script ---"
              # Definição de Variáveis Shell (usando vars do Terraform)
              REGION="${var.aws_region}"
              PROJECT_NAME="${var.project_name}"
              GITHUB_REPO_URL="${var.github_repo_url}"
              PROJECT_DIR="${var.project_dir_on_server}"
              DB_PATH="${var.db_path_on_server}"
              DB_DIR=$(dirname "$DB_PATH")
              VENV_DIR="$PROJECT_DIR/venv"
              STATIC_DIR="$PROJECT_DIR/staticfiles"
              ENV_FILE="$PROJECT_DIR/.env"
              SSM_PARAM_NAME="/$${PROJECT_NAME}/SECRET_KEY"
              GUNICORN_SOCKET_FILE="/etc/systemd/system/gunicorn.socket"
              GUNICORN_SERVICE_FILE="/etc/systemd/system/gunicorn.service"
              NGINX_CONF_FILE="/etc/nginx/conf.d/$${PROJECT_NAME}.conf"

              # 1. Atualizar Sistema e Instalar Dependências Base
              echo "--- Atualizando sistema e instalando pacotes ---"
              dnf update -y
              dnf install git python3 python3-pip nginx aws-cli -y
              echo "--- Pacotes instalados ---"

              # 2. Criar Diretórios
              echo "--- Criando diretórios ---"
              mkdir -p "$DB_DIR"
              echo "Diretório DB: $DB_DIR"
              mkdir -p "$PROJECT_DIR" # Garante que o diretório do projeto existe antes do clone
              echo "Diretório Projeto: $PROJECT_DIR"

              # 3. Clonar Repositório
              echo "--- Clonando repositório $GITHUB_REPO_URL para $PROJECT_DIR ---"
              # Verifica se o diretório já tem algo (evita erro em re-runs parciais)
              if [ -d "$PROJECT_DIR/.git" ]; then
                echo "Diretório $PROJECT_DIR já existe e parece ser um repo git. Pulando clone."
                cd "$PROJECT_DIR"
                # Poderia adicionar um 'git pull' aqui se desejasse atualizar
              else
                git clone "$GITHUB_REPO_URL" "$PROJECT_DIR"
                cd "$PROJECT_DIR"
              fi
              echo "--- Repositório clonado (ou existente) ---"

              # 4. Ajustar Permissões Iniciais
              echo "--- Ajustando permissões para ec2-user ---"
              # Garante que o ec2-user seja dono de tudo após o clone/pull
              chown -R ec2-user:ec2-user "$PROJECT_DIR"
              chown -R ec2-user:ec2-user "$DB_DIR"
              echo "--- Permissões ajustadas ---"

              # 5. Criar e Ativar Ambiente Virtual & Instalar Dependências Python
              echo "--- Configurando ambiente Python em $VENV_DIR ---"
              # Criar venv como ec2-user
              sudo -u ec2-user python3 -m venv "$VENV_DIR"
              # Instalar dependências (script user-data roda como root)
              "$VENV_DIR/bin/pip" install --upgrade pip
              "$VENV_DIR/bin/pip" install -r requirements.txt
              echo "--- Ambiente Python configurado ---"

              # 6. Criar Arquivo de Ambiente (.env) - Buscando Secret Key do SSM
              echo "--- Criando arquivo .env em $ENV_FILE ---"
              echo "Buscando parâmetro: $SSM_PARAM_NAME na região $REGION"
              # Tenta buscar a chave, redireciona erro para log se falhar
              SECRET_KEY_VALUE=$(aws ssm get-parameter --name "$SSM_PARAM_NAME" --with-decryption --query Parameter.Value --output text --region "$REGION" 2>/var/log/ssm_error.log)
              if [ -z "$SECRET_KEY_VALUE" ]; then
                  echo "ERRO CRÍTICO: Falha ao buscar SECRET_KEY do SSM Parameter Store ($SSM_PARAM_NAME)!"
                  echo "Verifique /var/log/ssm_error.log para detalhes."
                  echo "Verifique nome do parâmetro, região ($REGION) e permissões IAM da instância."
                  exit 1
              fi
              INSTANCE_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
              echo "IP Privado da Instância: $INSTANCE_PRIVATE_IP"

              cat <<EOT > "$ENV_FILE"
SECRET_KEY='$SECRET_KEY_VALUE'
DEBUG=False
ALLOWED_HOSTS='$INSTANCE_PRIVATE_IP' # Considere adicionar outros hosts se necessário (e.g., DNS)
DATABASE_URL='sqlite:///$DB_PATH'
STATIC_ROOT='$STATIC_DIR'
EOT
              chown ec2-user:ec2-user "$ENV_FILE"
              chmod 600 "$ENV_FILE" # Permissões restritas para o .env
              echo "--- Arquivo .env criado ---"

              # 7. Rodar Migrações e Coletar Estáticos (como ec2-user)
              echo "--- Executando migrate e collectstatic ---"
              sudo -u ec2-user touch "$DB_PATH" # Garante que o arquivo existe
              sudo -u ec2-user "$VENV_DIR/bin/python" manage.py migrate --noinput
              sudo -u ec2-user "$VENV_DIR/bin/python" manage.py collectstatic --noinput --clear
              # Garante permissão na pasta staticfiles após collectstatic
              chown -R ec2-user:ec2-user "$STATIC_DIR"
              echo "--- Migrations e Collectstatic concluídos ---"

              # 8. Configurar Gunicorn (Systemd Socket + Service)
              echo "--- Configurando Gunicorn systemd ---"
              # Gunicorn Socket
              cat <<EOT > "$GUNICORN_SOCKET_FILE"
[Unit]
Description=gunicorn socket for $PROJECT_NAME

[Socket]
ListenStream=/run/gunicorn.sock
SocketUser=ec2-user
# --- CORREÇÃO APLICADA AQUI ---
SocketGroup=nginx   # Nginx precisa de acesso ao socket
SocketMode=660      # Permite leitura/escrita para user e group
# --- FIM DA CORREÇÃO ---

[Install]
WantedBy=sockets.target
EOT

              # Gunicorn Service
              cat <<EOT > "$GUNICORN_SERVICE_FILE"
[Unit]
Description=gunicorn daemon for $PROJECT_NAME
Requires=gunicorn.socket # Garante que o socket esteja pronto
After=network.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$ENV_FILE # Carrega variáveis do .env
# ExecStart aponta para o gunicorn dentro do venv
# Substitua 'myproject.wsgi:application' pelo caminho correto se seu projeto não for 'myproject'
ExecStart=$VENV_DIR/bin/gunicorn \\
          --access-logfile - \\
          --error-logfile - \\
          --workers 3 \\
          --bind unix:/run/gunicorn.sock \\
          myproject.wsgi:application
Restart=always # Reinicia se falhar
RestartSec=5   # Espera 5s antes de reiniciar

[Install]
WantedBy=multi-user.target
EOT

              # Define permissões nos arquivos de configuração do systemd
              chmod 644 "$GUNICORN_SOCKET_FILE"
              chmod 644 "$GUNICORN_SERVICE_FILE"
              echo "--- Arquivos Gunicorn systemd criados ---"

              # 9. Configurar Nginx (Reverse Proxy)
              echo "--- Configurando Nginx ---"
              # Remove configuração padrão para evitar conflitos
              rm -f /etc/nginx/sites-enabled/default # Comum em Ubuntu/Debian
              rm -f /etc/nginx/conf.d/default.conf  # Comum em CentOS/Fedora/Amazon Linux

              # Cria o arquivo de configuração Nginx
              cat <<EOT > "$NGINX_CONF_FILE"
server {
    listen 80 default_server;
    server_name $INSTANCE_PRIVATE_IP _;

    # Logs específicos para este site
    access_log /var/log/nginx/$${PROJECT_NAME}_access.log;
    error_log /var/log/nginx/$${PROJECT_NAME}_error.log;

    # Otimização para servir arquivos estáticos
    location /static/ {
        alias $STATIC_DIR/; # Caminho definido no .env e collectstatic
        expires 7d;        # Cache no browser por 7 dias
        access_log off;    # Não logar acesso a estáticos (opcional)
    }

    # Tratar favicon separadamente (opcional)
    location = /favicon.ico {
        alias $STATIC_DIR/favicon.ico; # Ajuste se necessário
        log_not_found off;
        access_log off;
    }

    # Passar todas as outras requisições para o Gunicorn via socket
    location / {
        proxy_set_header Host \$host; # Envia o Host header original
        proxy_set_header X-Real-IP \$remote_addr; # Envia o IP real do cliente
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; # Lista de IPs (proxy)
        proxy_set_header X-Forwarded-Proto \$scheme; # http ou https
        # Conecta ao socket do Gunicorn
        proxy_pass http://unix:/run/gunicorn.sock;
    }
}
EOT
              # Define permissões no arquivo de configuração do Nginx
              chmod 644 "$NGINX_CONF_FILE"
              echo "--- Validando configuração Nginx ---"
              nginx -t # Testa a sintaxe da configuração Nginx
              if [ $? -ne 0 ]; then
                  echo "ERRO CRÍTICO: Configuração do Nginx inválida! Verifique $NGINX_CONF_FILE e os logs do Nginx."
                  exit 1 # Aborta o script se a config for inválida
              fi
              echo "--- Configuração Nginx criada e validada ---"

              # 10. Habilitar e Iniciar Serviços systemd
              echo "--- Habilitando e iniciando serviços systemd ---"
              systemctl daemon-reload # Recarrega configs do systemd
              systemctl enable --now gunicorn.socket # Habilita e inicia o socket Gunicorn
              systemctl enable --now gunicorn.service # Habilita e inicia o serviço Gunicorn
              systemctl enable nginx # Habilita Nginx para iniciar no boot
              systemctl restart nginx # Reinicia Nginx para aplicar nova config e garantir que está rodando
              echo "--- Serviços Gunicorn e Nginx configurados e iniciados ---"

              # 11. (Opcional) Configurar Backup do SQLite para S3 via Cron
              echo "AVISO: Backup do SQLite via cron não configurado neste script."

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

  # Garante que a role/profile e o SG existem antes de criar a instância
  depends_on = [aws_security_group.app_sg, aws_iam_instance_profile.ec2_s3_backup_profile]
}

# === Outputs ===
output "instance_private_ip" {
  description = "Endereco IP Privado da instancia EC2 criada"
  value       = aws_instance.app_server.private_ip
}

# Removidos outputs de IP público/DNS pois associate_public_ip_address = false
# output "instance_public_ip" { ... }
# output "instance_public_dns" { ... }

output "instance_iam_role_name" {
  description = "Nome da IAM Role associada a instancia EC2"
  value       = aws_iam_role.ec2_s3_backup_role.name
}

output "instance_iam_profile_name" {
  description = "Nome do IAM Instance Profile associado a instancia EC2"
  value       = aws_iam_instance_profile.ec2_s3_backup_profile.name
}