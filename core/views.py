# core/views.py

import boto3
import logging
from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.conf import settings

logger = logging.getLogger(__name__)

@login_required
def home(request):
    context = {
        'backups': [],
        's3_error': None
    }
    backup_files_list = []

    try:
        # Obter todas as credenciais e configurações das settings
        aws_key = getattr(settings, 'AWS_ACCESS_KEY_ID', None)
        aws_secret = getattr(settings, 'AWS_SECRET_ACCESS_KEY', None)
        aws_token = getattr(settings, 'AWS_SESSION_TOKEN', None) # <<< OBTER O TOKEN
        aws_region = getattr(settings, 'AWS_S3_REGION_NAME', None)
        bucket_name = getattr(settings, 'S3_BUCKET_NAME', None)

        if not bucket_name:
             raise ValueError("S3_BUCKET_NAME não está configurado em settings.py")
        if aws_key and aws_key.startswith('ASIA') and not aws_token: # Verifica se precisa de token
             raise ValueError("AWS_SESSION_TOKEN é necessário para credenciais temporárias (ASIA...) mas não foi encontrado nas configurações.")

        target_bucket_arn = f"arn:aws:s3:::{bucket_name}"
        logger.info(f"Tentando acessar o bucket S3 com ARN (construído): {target_bucket_arn}")
        logger.info(f"Iniciando consulta ao S3. Bucket: {bucket_name}, Região: {aws_region}")

        # Cria o cliente S3 passando o token de sessão
        s3_client = boto3.client(
            's3',
            aws_access_key_id=aws_key,
            aws_secret_access_key=aws_secret,
            # aws_session_token=aws_token, # REMOVA ou comente esta linha
            region_name=aws_region
        )

        prefix = 'AB_CADASTROPOSITIVO_'
        suffix = '.bak'

        logger.debug(f"Listando objetos com prefixo: '{prefix}'")
        response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

        if 'Contents' in response:
            for obj in response['Contents']:
                key = obj['Key']
                if key.endswith(suffix):
                    backup_files_list.append({
                        'filename': key,
                        'last_modified': obj['LastModified'],
                        'size': obj['Size']
                    })
            logger.info(f"Encontrados {len(backup_files_list)} arquivos de backup correspondentes.")
        else:
            logger.info("Nenhum objeto encontrado no bucket com o prefixo especificado.")

        context['backups'] = backup_files_list

    except ValueError as ve:
         logger.error(f"Erro de configuração: {ve}")
         context['s3_error'] = f"Erro de Configuração: {ve}. Verifique seu arquivo settings.py."
    except Exception as e:
        logger.error(f"Erro inesperado ao acessar S3: {e}", exc_info=True)
        context['s3_error'] = f"Erro ao acessar S3 ({type(e).__name__}). Verifique as credenciais, permissões, configuração e logs do servidor."

    context['s3_bucket_name'] = getattr(settings, 'S3_BUCKET_NAME', 'N/A')

    return render(request, 'core/home.html', context)