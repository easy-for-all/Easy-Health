# Backup e restore de producao

Use estes procedimentos apenas na VPS de producao, a partir da raiz do repositorio.

## Backup manual

```bash
bash scripts/production/backup_production.sh
```

O script cria uma pasta com timestamp em:

```bash
/backups/easy-health/YYYY-MM-DD_HH-mm-ss
```

Se a VPS nao permitir escrita em `/backups/easy-health`, o fallback e:

```bash
./backups/production/YYYY-MM-DD_HH-mm-ss
```

## Conteudo do backup

- `database.dump`: dump completo PostgreSQL em formato custom com blobs.
- `uploads.tar.gz`: arquivos de `/rails/storage`, quando a pasta existir.
- `schema.sql`: schema SQL atual.
- `manifest.json`: app, ambiente, timestamp, commit, arquivos e status.
- `docker-containers.txt`: containers do compose.
- `docker-volumes.txt`: volumes Docker.
- `postgres-container-inspect.json`: detalhes do container do banco.
- `api-container-inspect.json`: detalhes do container da API, quando disponivel.
- `env.backup` ou `env.production.backup`, se existir na VPS.

Arquivos `.env` copiados para backup ficam somente na VPS e nao devem ser commitados.

## Restore de emergencia

O restore nunca roda automaticamente no deploy.

Execute apenas se for realmente necessario recuperar dados:

```bash
bash scripts/production/restore_production.sh /backups/easy-health/YYYY-MM-DD_HH-mm-ss
```

O script exige confirmacao manual:

```bash
RESTORE_PRODUCTION
```

Ele para `api` e `web` sem apagar volumes, restaura o banco com `pg_restore`, extrai uploads sobre `/rails/storage` sem remover o volume e roda verificacao de persistencia.

## Validar dados protegidos

```bash
bash scripts/production/check_persistence.sh
```

Saida esperada:

```bash
DATABASE OK
USERS: X
WORKOUT PLANS: Y
WORKOUT SESSIONS: Z
USER MEDIA: N
ACTIVE STORAGE BLOBS: N
UPLOAD FILES: N
STORAGE SIZE: X
PERSISTENCE CHECK OK
```

## Checklist de backup antes de deploy

- `database.dump` existe e tem tamanho maior que zero.
- `manifest.json` contem `"status": "success"`.
- `uploads.tar.gz` existe quando ha `/rails/storage`.
- `docker-volumes.txt` lista volumes de producao.
- `git-commit.txt` registra a versao antes do deploy.

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
Nunca substituir o fluxo seguro por comandos manuais sem backup.
