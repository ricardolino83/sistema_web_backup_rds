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
  description = "ID da VPC onde os recursos serão criados (Substitua ou use data source)"
  type        = string
  default = "vpc-01949bdd15953d7ae"
}

variable "subnet_id" {
  description = "ID da Subnet pública onde a instância EC2 será criada (Substitua ou use data source)"
  type        = string
  default = "subnet-0ac0015f3c048a81d"
}

variable "ami_id" {
  description = "ID da AMI Amazon Linux 2023 para a região sa-east-1 (!!! ENCONTRE E ATUALIZE !!!)"
  type        = string
  default = "ami-0eab6be2916bd677c"
}

variable "instance_type" {
  description = "Tipo da instância EC2"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Nome do Key Pair EC2 para acesso SSH"
  type        = string
  default = "Ricardo Lino - Prod"
}

variable "s3_backup_bucket_name" {
  description = "Nome do bucket S3 para backups (Deve existir)"
  type        = string
  default = "mybackuprdscorebank"
}

variable "allowed_ssh_cidr" {
  description = "Bloco CIDR permitido para acesso SSH (porta 22). Use seu IP/32 ou 0.0.0.0/0 com cuidado."
  type        = list(string)
  default     = ["10.3.0.138/32"] # Recomendado restringir para seu IP: ["SEU_IP/32"]
}

variable "allowed_http_cidr" {
  description = "Bloco CIDR permitido para acesso HTTP/HTTPS (portas 80, 443)."
  type        = list(string)
  default     = ["10.3.0.138/32"] # Para acesso público web
}

variable "github_repo_url" {
  description = "URL do repositório GitHub (HTTPS ou SSH)"
  type        = string
  default = "https://github.com/ricardolino83/sistema_web_backup_rds.git"
}

variable "project_dir_on_server" {
  description = "Diretório onde o projeto será clonado no servidor"
  type        = string
  default     = "/opt/sistema_web_backup_rds"
}

variable "db_path_on_server" {
  description = "Caminho completo para o arquivo SQLite no servidor"
  type        = string
  default     = "/opt/data/sistema_web_backup_rds/db.sqlite3"
}