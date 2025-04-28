# core/views.py

import boto3
import logging # Importar logging
from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.conf import settings

# Configurar um logger para esta view (boa prática)
logger = logging.getLogger(__name__)

@login_required
def home(request):
    # Inicializa o contexto que será passado para o template
    context = {
        'backups': [],  # Começa com lista vazia
        's3_error': None # Começa sem erro
    }
    backup_files_list = [] # Lista temporária para coletar arquivos

    try:
        # Tenta obter as configurações do S3
        aws_key = getattr(settings, 'AWS_ACCESS_KEY_ID', None)
        aws_secret = getattr(settings, 'AWS_SECRET_ACCESS_KEY', None)
        aws_region = getattr(settings, 'AWS_S3_REGION_NAME', None)
        bucket_name = getattr(settings, 'S3_BUCKET_NAME', None)

        # Verifica se as configurações essenciais existem (exceto chaves, se usar IAM Role)
        if not bucket_name:
             raise ValueError("S3_BUCKET_NAME não está configurado em settings.py")
        # if not aws_region: # Região pode não ser estritamente necessária dependendo da config S3
        #     raise ValueError("AWS_S3_REGION_NAME não está configurado em settings.py")

        logger.info(f"Iniciando consulta ao S3. Bucket: {bucket_name}, Região: {aws_region}")

        # Cria o cliente S3. Se rodar no EC2 com IAM Role,
        # não precisa passar as chaves/segredo explicitamente.
        s3_client = boto3.client(
            's3',
            aws_access_key_id=aws_key,
            aws_secret_access_key=aws_secret,
            region_name=aws_region
        )

        prefix = 'AB_CADASTROPOSITIVO_'
        suffix = '.bak'

        logger.debug(f"Listando objetos com prefixo: '{prefix}'")
        response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

        if 'Contents' in response:
            for obj in response['Contents']:
                key = obj['Key']
                # Filtro duplo (prefixo na chamada, sufixo aqui)
                if key.endswith(suffix):
                    backup_files_list.append({
                        'filename': key,
                        'last_modified': obj['LastModified'],
                        'size': obj['Size']
                    })
            logger.info(f"Encontrados {len(backup_files_list)} arquivos de backup correspondentes.")
        else:
            logger.info("Nenhum objeto encontrado no bucket com o prefixo especificado.")

        # Adiciona a lista ao contexto final
        context['backups'] = backup_files_list

    except ValueError as ve:
         logger.error(f"Erro de configuração: {ve}")
         context['s3_error'] = f"Erro de Configuração: {ve}. Verifique seu arquivo settings.py."
    except Exception as e:
        # Captura outros erros (permissão, conexão, etc.)
        logger.error(f"Erro inesperado ao acessar S3: {e}", exc_info=True) # Log completo do erro
        context['s3_error'] = f"Erro ao acessar S3 ({type(e).__name__}). Verifique as permissões, configuração e logs do servidor."

    # Passa o nome do bucket para o template também, se existir
    context['s3_bucket_name'] = getattr(settings, 'S3_BUCKET_NAME', 'N/A')

    # Renderiza o template home.html com o contexto atualizado
    return render(request, 'core/home.html', context)

# A função list_s3_backups foi removida.