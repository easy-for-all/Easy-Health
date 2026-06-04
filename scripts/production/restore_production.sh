#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
WEB_SERVICE="${WEB_SERVICE:-web}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
STORAGE_PATH="${STORAGE_PATH:-/rails/storage}"

log() {
  printf '[restore-production] %s\n' "$*"
}

fail() {
  printf '[restore-production] ERRO: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

backup_dir="${1:-}"
[ -n "$backup_dir" ] || fail "uso: $0 /backups/easy-health/YYYY-MM-DD_HH-mm-ss"
[ -d "$backup_dir" ] || fail "backup nao encontrado: $backup_dir"
[ -s "$backup_dir/database.dump" ] || fail "database.dump ausente ou vazio"

printf 'ATENCAO: restore em producao sobrescreve dados atuais do banco e storage.\n'
printf 'Digite RESTORE_PRODUCTION para continuar: '
read -r confirmation
[ "$confirmation" = "RESTORE_PRODUCTION" ] || fail "confirmacao invalida; restore cancelado"

log "Parando aplicacao sem apagar volumes"
compose stop "$WEB_SERVICE" "$API_SERVICE"

log "Garantindo que o banco esteja ativo"
compose up -d "$DB_SERVICE"
compose exec -T "$DB_SERVICE" sh -lc "pg_isready -U '$DB_USER' -d '$DB_NAME'" >/dev/null

log "Restaurando banco com pg_restore"
compose exec -T "$DB_SERVICE" sh -lc "pg_restore -U '$DB_USER' -d '$DB_NAME' --clean --if-exists --no-owner --verbose" < "$backup_dir/database.dump"

if [ -s "$backup_dir/uploads.tar.gz" ]; then
  log "Restaurando uploads/imagens/exames"
  compose up -d "$API_SERVICE"
  compose exec -T "$API_SERVICE" mkdir -p "$STORAGE_PATH"
  log "Extraindo backup sobre o storage atual sem apagar volume ou pasta persistente"
  compose exec -T "$API_SERVICE" tar -C "$(dirname "$STORAGE_PATH")" -xzf - < "$backup_dir/uploads.tar.gz"
else
  log "Backup de uploads nao encontrado; etapa de storage ignorada"
fi

log "Subindo aplicacao"
compose up -d
sleep 10

log "Verificacao basica pos-restore"
bash scripts/production/check_persistence.sh

printf 'RESTORE DE PRODUCAO CONCLUIDO\n'
