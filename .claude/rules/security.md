# Security Rules — Easy Health

## Autenticação
- Usar Rails session/cookie ou Devise no MVP.
- Não implementar JWT customizado no MVP.
- Token auth só deve ser considerada para mobile no futuro.

## Dados sensíveis
- Nunca salvar senha em texto.
- Nunca expor dados sensíveis em logs.
- Não retornar informações pessoais desnecessárias nas APIs.

## Dados Pessoais
- anonimizar ou mascarar dados pessoais
- sempre perguntar quando for trabalhar com dados pessoais, inclusive fotos

## Validação
- Validar todo input no backend.
- Sanitizar campos de texto livre.
- Proteger endpoints autenticados.

## Uploads
- Validar tipo e tamanho de arquivos.
- Usar storage S3-compatible para imagens.
- Nunca confiar no MIME type enviado pelo cliente.

## Boas práticas
- Usar HTTPS em produção.
- Usar variáveis de ambiente para secrets.
- Nunca commitar `.env`, tokens ou chaves.