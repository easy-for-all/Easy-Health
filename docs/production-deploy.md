# Deploy seguro de producao

Este projeto tem clientes reais em producao. Todo deploy deve preservar banco, uploads, exames, imagens, treinos, historico e dados de billing.

## Comando oficial

Execute sempre a partir da raiz do repositorio na VPS:

```bash
bash scripts/production/safe_deploy.sh
```

Para uma versao especifica:

```bash
bash scripts/production/safe_deploy.sh <commit-ou-ref>
```

O GitHub Actions tambem deve chamar esse script na VPS.

## O que o deploy seguro faz

1. Roda `scripts/production/pre_deploy_guard.sh`.
2. Verifica ambiente de producao, volumes, banco e storage.
3. Executa backup obrigatorio com `scripts/production/backup_production.sh`.
4. Bloqueia o deploy se o backup falhar.
5. Atualiza o codigo para a ref desejada.
6. Sobe/rebuilda containers sem apagar volumes.
7. Roda migrations incrementais com `bin/rails db:migrate`.
8. Valida migrations criticas em `schema_migrations`.
9. Roda `bin/rails blocks:backfill_single_blocks` e `bin/rails blocks:assert_no_null_workout_blocks`.
10. Audita o catalogo gifdotreino com `bin/rails exercises:purge_non_gifdotreino DRY_RUN=1`.
11. Roda healthcheck.
12. Valida contagens minimas antes/depois do deploy.
13. Roda `scripts/production/check_persistence.sh`.

## Dados protegidos

- Usuarios cadastrados.
- Planos de treino criados.
- Treinos realizados e sessoes de treino.
- Fotos, exames e uploads via ActiveStorage local.
- Dados computados de saude.
- Assinaturas, billing e eventos Stripe.

## Persistencia esperada

- Postgres: volume Docker nomeado `pg_data` montado em `/var/lib/postgresql/data`.
- ActiveStorage local: volume Docker nomeado `storage_data` montado em `/rails/storage`.
- Compose oficial: `docker-compose.prod.yml`.
- Servico do banco: `db`.
- Servico Rails: `api`.
- Database: `easy_health_production`.

## Comandos proibidos em producao

Nunca usar:

```bash
docker compose down -v
docker volume rm
rails db:reset
rails db:drop
rails db:setup
rm -rf storage
```

Nunca apagar volumes Docker de producao.
Nunca remover a pasta de storage/uploads.
Nunca fazer deploy sem backup concluido com sucesso.

## Checklist antes do deploy

- Confirmar que a VPS esta no diretorio `/home/easy/Easy-Health`.
- Confirmar que `docker compose -f docker-compose.prod.yml ps` mostra `db`, `api` e `web`.
- Confirmar que `pg_data` e `storage_data` existem.
- Rodar `bash scripts/production/check_persistence.sh`.
- Rodar o deploy apenas com `bash scripts/production/safe_deploy.sh`.

## Se o deploy for bloqueado

Se aparecer:

```bash
DEPLOY BLOQUEADO: backup de producao falhou.
```

Nao force o deploy. Verifique permissao em `/backups/easy-health`, espaco em disco, saude do container `db`, saude do container `api` e existencia de `/rails/storage`.

## Operacoes de manutencao

- Para validar blocos de treino, use `bin/rails blocks:backfill_single_blocks` seguido de `bin/rails blocks:assert_no_null_workout_blocks`.
- Para auditar exercicios fora do catalogo gifdotreino, use `bin/rails exercises:purge_non_gifdotreino DRY_RUN=1`.
- Evite `rails runner` longos com aspas aninhadas em producao; prefira rake tasks versionadas e revisaveis no repositorio.
