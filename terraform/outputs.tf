# terraform/outputs.tf

output "instance_id" {
  description = "O ID da instância EC2 criada."
  value       = aws_instance.app_server.id
}

output "public_ip" {
  description = "O endereço IP público da instância EC2."
  # value       = aws_eip.app_eip.public_ip # Use se criou um Elastic IP
  value       = aws_instance.app_server.public_ip # Usa o IP público dinâmico se não usar EIP
}

output "public_dns" {
  description = "O DNS público da instância EC2."
  value       = aws_instance.app_server.public_dns
}