#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
STORAGE_PATH="${STORAGE_PATH:-/rails/storage}"

log() {
  printf '[pre-deploy-guard] %s\n' "$*"
}

fail() {
  printf '[pre-deploy-guard] ERRO: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

block_dangerous_commands() {
  log "Procurando comandos destrutivos no fluxo de deploy"
  scan_paths=".github/workflows scripts"
  if [ -d ".github/workflows" ] || [ -d "scripts" ]; then
    if grep -RInE 'docker[[:space:]]+compose[^#\n]*down[[:space:]][^#\n]*-v|docker[[:space:]]+volume[[:space:]]+rm|rails[[:space:]]+db:(reset|drop|setup)|bin/rails[[:space:]]+db:(reset|drop|setup)|rm[[:space:]]+-rf[[:space:]]+([^#\n]*\/)?storage' $scan_paths \
      --exclude='restore_production.sh' \
      --exclude='pre_deploy_guard.sh' 2>/dev/null; then
      fail "comando destrutivo encontrado no fluxo de deploy"
    fi
  fi
}

confirm_production() {
  [ -f "$COMPOSE_FILE" ] || fail "compose de producao nao encontrado: $COMPOSE_FILE"
  grep -q 'RAILS_ENV: production' "$COMPOSE_FILE" || fail "compose nao declara RAILS_ENV production"
  grep -q 'pg_data:/var/lib/postgresql/data' "$COMPOSE_FILE" || fail "volume persistente pg_data nao encontrado no compose"
  grep -q 'storage_data:/rails/storage' "$COMPOSE_FILE" || fail "volume persistente storage_data nao encontrado no compose"
}

check_runtime() {
  log "Verificando containers, volumes, banco e storage"
  db_container="$(compose ps -q "$DB_SERVICE")"
  api_container="$(compose ps -q "$API_SERVICE")"
  [ -n "$db_container" ] || fail "container do banco nao encontrado para service=$DB_SERVICE"
  [ -n "$api_container" ] || fail "container da API nao encontrado para service=$API_SERVICE"

  docker inspect "$db_container" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' | grep -q 'pg_data' || fail "Postgres nao esta montado em volume pg_data"
  docker inspect "$api_container" --format '{{range .Mounts}}{{if eq .Destination "/rails/storage"}}{{.Name}}{{end}}{{end}}' | grep -q 'storage_data' || fail "API nao esta montada em volume storage_data"

  compose exec -T "$DB_SERVICE" sh -lc "pg_isready -U '$DB_USER' -d '$DB_NAME'" >/dev/null || fail "banco nao responde"
  compose exec -T "$API_SERVICE" test -d "$STORAGE_PATH" || fail "pasta de uploads nao existe: $STORAGE_PATH"
}

confirm_production
block_dangerous_commands
check_runtime

log "Executando backup obrigatorio antes do deploy"
if bash scripts/production/backup_production.sh; then
  log "Backup concluido; deploy autorizado"
else
  printf 'DEPLOY BLOQUEADO: backup de producao falhou.\n' >&2
  exit 1
fi
