#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Easy Health"
ENVIRONMENT="production"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
STORAGE_PATH="${STORAGE_PATH:-/rails/storage}"
BACKUP_ROOT_PRIMARY="${BACKUP_ROOT_PRIMARY:-/backups/easy-health}"
BACKUP_ROOT_FALLBACK="${BACKUP_ROOT_FALLBACK:-./backups/production}"

log() {
  printf '[backup-production] %s\n' "$*"
}

fail() {
  printf '[backup-production] ERRO: %s\n' "$*" >&2
  exit 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

choose_backup_root() {
  if mkdir -p "$BACKUP_ROOT_PRIMARY" 2>/dev/null; then
    printf '%s' "$BACKUP_ROOT_PRIMARY"
    return
  fi

  mkdir -p "$BACKUP_ROOT_FALLBACK"
  printf '%s' "$BACKUP_ROOT_FALLBACK"
}

require_file() {
  if [ ! -f "$1" ] || [ ! -s "$1" ]; then
    fail "arquivo obrigatorio nao foi criado ou esta vazio: $1"
  fi
}

timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
backup_root="$(choose_backup_root)"
backup_dir="${backup_root}/${timestamp}"

mkdir -p "$backup_dir"

log "Iniciando backup de producao em $backup_dir"
log "Compose: $COMPOSE_FILE"
log "Banco: service=$DB_SERVICE db=$DB_NAME user=$DB_USER"
log "Storage: service=$API_SERVICE path=$STORAGE_PATH"

[ -f "$COMPOSE_FILE" ] || fail "compose de producao nao encontrado: $COMPOSE_FILE"

db_container="$(compose ps -q "$DB_SERVICE")"
[ -n "$db_container" ] || fail "container do Postgres nao encontrado para service=$DB_SERVICE"

api_container="$(compose ps -q "$API_SERVICE" || true)"

git_commit="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"

log "Salvando metadados Docker e Git"
date -Iseconds > "$backup_dir/backup-created-at.txt"
printf '%s\n' "$git_commit" > "$backup_dir/git-commit.txt"
compose ps > "$backup_dir/docker-containers.txt"
docker volume ls > "$backup_dir/docker-volumes.txt"
docker inspect "$db_container" > "$backup_dir/postgres-container-inspect.json"
if [ -n "$api_container" ]; then
  docker inspect "$api_container" > "$backup_dir/api-container-inspect.json"
fi

if [ -f ".env.production" ]; then
  cp ".env.production" "$backup_dir/env.production.backup"
  chmod 600 "$backup_dir/env.production.backup" || true
elif [ -f ".env" ]; then
  cp ".env" "$backup_dir/env.backup"
  chmod 600 "$backup_dir/env.backup" || true
fi

log "Verificando existencia do banco de dados"
db_exists="$(compose exec -T "$DB_SERVICE" sh -lc "psql -U '$DB_USER' -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\"" 2>/dev/null || true)"
if [ "$db_exists" != "1" ]; then
  log "Banco '$DB_NAME' nao existe ainda — nada a preservar; backup ignorado"
  printf '\nBACKUP IGNORADO (banco nao inicializado)\n'
  exit 0
fi

log "Gerando dump PostgreSQL"
compose exec -T "$DB_SERVICE" sh -lc "pg_dump -U '$DB_USER' -d '$DB_NAME' --format=custom --blobs --verbose" > "$backup_dir/database.dump"
require_file "$backup_dir/database.dump"

log "Gerando schema SQL"
compose exec -T "$DB_SERVICE" sh -lc "pg_dump -U '$DB_USER' -d '$DB_NAME' --schema-only --no-owner --no-privileges" > "$backup_dir/schema.sql"
require_file "$backup_dir/schema.sql"

uploads_backup=""
if [ -n "$api_container" ] && compose exec -T "$API_SERVICE" test -d "$STORAGE_PATH"; then
  log "Compactando uploads do ActiveStorage"
  compose exec -T "$API_SERVICE" tar -C "$(dirname "$STORAGE_PATH")" -czf - "$(basename "$STORAGE_PATH")" > "$backup_dir/uploads.tar.gz"
  require_file "$backup_dir/uploads.tar.gz"
  uploads_backup="uploads.tar.gz"
else
  log "Pasta de uploads nao encontrada; backup de uploads sera marcado como ausente"
  printf 'storage path not found: %s\n' "$STORAGE_PATH" > "$backup_dir/uploads-not-found.txt"
fi

log "Gerando manifest.json"
cat > "$backup_dir/manifest.json" <<EOF
{
  "app": "$(json_escape "$APP_NAME")",
  "environment": "$(json_escape "$ENVIRONMENT")",
  "timestamp": "$(json_escape "$timestamp")",
  "git_commit": "$(json_escape "$git_commit")",
  "database_backup": "database.dump",
  "uploads_backup": "$(json_escape "$uploads_backup")",
  "docker_containers": "docker-containers.txt",
  "docker_volumes": "docker-volumes.txt",
  "schema": "schema.sql",
  "status": "success"
}
EOF

require_file "$backup_dir/manifest.json"

printf '\nBACKUP CONCLUIDO COM SUCESSO\n'
printf 'Caminho: %s\n' "$backup_dir"
