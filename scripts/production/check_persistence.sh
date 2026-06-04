#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
STORAGE_PATH="${STORAGE_PATH:-/rails/storage}"

log() {
  printf '[persistence-check] %s\n' "$*"
}

fail() {
  printf '[persistence-check] ERRO: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

sql_count() {
  table="$1"
  compose exec -T "$DB_SERVICE" sh -lc "psql -U '$DB_USER' -d '$DB_NAME' -Atc \"select count(*) from ${table};\"" 2>/dev/null || printf 'ERROR'
}

storage_stat() {
  compose exec -T "$API_SERVICE" sh -lc "if [ -d '$STORAGE_PATH' ]; then find '$STORAGE_PATH' -type f | wc -l; else printf 'MISSING'; fi"
}

storage_size() {
  compose exec -T "$API_SERVICE" sh -lc "if [ -d '$STORAGE_PATH' ]; then du -sh '$STORAGE_PATH' | awk '{print \$1}'; else printf 'MISSING'; fi"
}

[ -f "$COMPOSE_FILE" ] || fail "compose de producao nao encontrado: $COMPOSE_FILE"

db_container="$(compose ps -q "$DB_SERVICE")"
api_container="$(compose ps -q "$API_SERVICE")"
[ -n "$db_container" ] || fail "container do banco nao encontrado"
[ -n "$api_container" ] || fail "container da API nao encontrado"

compose exec -T "$DB_SERVICE" sh -lc "pg_isready -U '$DB_USER' -d '$DB_NAME'" >/dev/null

users="$(sql_count users)"
workout_plans="$(sql_count workout_plans)"
workout_sessions="$(sql_count workout_sessions)"
user_media="$(sql_count user_media)"
active_storage_blobs="$(sql_count active_storage_blobs)"
upload_files="$(storage_stat)"
storage_total="$(storage_size)"

for value in "$users" "$workout_plans" "$workout_sessions" "$user_media" "$active_storage_blobs"; do
  [ "$value" != "ERROR" ] || fail "falha ao consultar contagens do banco"
done

printf 'DATABASE OK\n'
printf 'USERS: %s\n' "$users"
printf 'WORKOUT PLANS: %s\n' "$workout_plans"
printf 'WORKOUT SESSIONS: %s\n' "$workout_sessions"
printf 'USER MEDIA: %s\n' "$user_media"
printf 'ACTIVE STORAGE BLOBS: %s\n' "$active_storage_blobs"
printf 'UPLOAD FILES: %s\n' "$upload_files"
printf 'STORAGE SIZE: %s\n' "$storage_total"

log "Volumes do Postgres"
docker inspect "$db_container" --format '{{range .Mounts}}{{println .Name .Type .Destination}}{{end}}'

log "Volumes da API"
docker inspect "$api_container" --format '{{range .Mounts}}{{println .Name .Type .Destination}}{{end}}'

if docker inspect "$db_container" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' | grep -q 'pg_data'; then
  :
else
  fail "Postgres nao parece usar o volume nomeado persistente pg_data"
fi

if docker inspect "$api_container" --format '{{range .Mounts}}{{if eq .Destination "/rails/storage"}}{{.Name}}{{end}}{{end}}' | grep -q 'storage_data'; then
  :
else
  fail "API nao parece usar o volume nomeado persistente storage_data em /rails/storage"
fi

[ "$upload_files" != "MISSING" ] || fail "pasta de uploads nao existe em $STORAGE_PATH"

printf 'PERSISTENCE CHECK OK\n'
