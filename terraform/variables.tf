# terraform/variables.tf

variable "aws_region" {
  description = "Região AWS para criar os recursos."
  type        = string
  default     = "sa-east-1" # ATUALIZADO para sua região
}

variable "instance_type" {
  description = "Tipo da instância EC2."
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Nome base para identificar os recursos."
  type        = string
  default     = "SistemaWebBackupRDS"
}

variable "s3_backup_bucket_name" {
  description = "Nome do bucket S3 onde estão os backups."
  type        = string
  default     = "mybackuprdscorebank"
}

variable "target_vpc_id" {
  description = "O ID da VPC existente onde os recursos serão criados."
  type        = string
  default     = "vpc-01949bdd15953d7ae" # ATUALIZADO com seu VPC ID
}

variable "target_subnet_id" {
  description = "O ID da Subnet existente DENTRO da target_vpc_id onde a instância EC2 será lançada."
  type        = string
  default     = "subnet-0ac0015f3c048a81d" # ATUALIZADO com sua Subnet ID
}

variable "allowed_ip_cidr" {
  description = "O bloco CIDR do IP permitido para acessar a instância (ex: SSH, HTTP/S)."
  type        = string
  default     = "10.3.0.138/32" # ATUALIZADO - /32 especifica um único IP
}

# variable "my_ip_for_ssh" { # Removido ou substituído por allowed_ip_cidr }