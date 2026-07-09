#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
WEB_SERVICE="${WEB_SERVICE:-web}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
TARGET_REF="${1:-${GIT_COMMIT:-origin/main}}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://localhost:3001/up}"

log() {
  printf '[safe-deploy] %s\n' "$*"
}

fail() {
  printf '[safe-deploy] ERRO: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

sql_count() {
  table="$1"
  compose exec -T "$DB_SERVICE" sh -lc "psql -U '$DB_USER' -d '$DB_NAME' -Atc \"select count(*) from ${table};\""
}

assert_migration_applied() {
  version="$1"
  applied="$(compose exec -T "$DB_SERVICE" sh -lc "psql -U '$DB_USER' -d '$DB_NAME' -Atc \"select count(*) from schema_migrations where version = '${version}';\"")"
  [ "$applied" = "1" ] || fail "migration critica pendente: $version"
}

validate_critical_migrations() {
  log "Validando migrations criticas"
  for version in 20260706130000 20260709020100 20260709020102 20260709152000; do
    assert_migration_applied "$version"
  done
}

write_snapshot() {
  file="$1"
  {
    printf 'users=%s\n' "$(sql_count users)"
    printf 'workout_plans=%s\n' "$(sql_count workout_plans)"
    printf 'workout_sessions=%s\n' "$(sql_count workout_sessions)"
    printf 'user_media=%s\n' "$(sql_count user_media)"
    printf 'active_storage_blobs=%s\n' "$(sql_count active_storage_blobs)"
  } > "$file"
}

read_snapshot_value() {
  file="$1"
  key="$2"
  grep "^${key}=" "$file" | cut -d= -f2
}

validate_no_drop() {
  before_file="$1"
  after_file="$2"
  for key in users workout_plans workout_sessions user_media active_storage_blobs; do
    before="$(read_snapshot_value "$before_file" "$key")"
    after="$(read_snapshot_value "$after_file" "$key")"
    if [ "$after" -lt "$before" ]; then
      fail "ALERTA CRITICO: contagem caiu para $key antes=$before depois=$after"
    fi
  done
}

copy_exercise_images() {
  log "Atualizando imagens locais de exercicios, se o dataset existir"
  dest="api/public/exercise-images/db"
  src="external/free-exercise-db/exercises"
  if [ ! -d "$src" ]; then
    log "Dataset external/free-exercise-db nao encontrado; etapa ignorada"
    return
  fi

  for slug in "$src"/*; do
    [ -d "$slug" ] || continue
    [ -f "$slug/0.jpg" ] || continue
    slug_name="$(basename "$slug")"
    mkdir -p "$dest/$slug_name"
    cp -u "$slug/0.jpg" "$dest/$slug_name/0.jpg"
  done
}

healthcheck() {
  log "Rodando healthcheck em $HEALTHCHECK_URL"
  for attempt in 1 2 3 4 5 6; do
    if curl -fsS "$HEALTHCHECK_URL" >/dev/null; then
      log "Healthcheck OK"
      return
    fi
    log "Healthcheck tentativa $attempt falhou; aguardando"
    sleep 5
  done
  fail "healthcheck falhou"
}

[ -f "$COMPOSE_FILE" ] || fail "compose de producao nao encontrado: $COMPOSE_FILE"

log "Iniciando deploy seguro para ref: $TARGET_REF"
bash scripts/production/pre_deploy_guard.sh

snapshot_dir="$(mktemp -d)"
before_snapshot="$snapshot_dir/before.env"
after_snapshot="$snapshot_dir/after.env"

log "Registrando contagens antes do deploy"
write_snapshot "$before_snapshot"

log "Atualizando codigo"
git fetch origin main
git reset --hard "$TARGET_REF"
git submodule update --init --recursive || true

if [ -f ".env" ]; then
  sed -i '/^GIT_COMMIT=/d' .env 2>/dev/null || true
  printf 'GIT_COMMIT=%s\n' "$TARGET_REF" >> .env
fi

copy_exercise_images

log "Rebuild e subida dos containers sem apagar volumes"
compose up -d --build

log "Aguardando API e banco"
sleep 15
compose exec -T "$DB_SERVICE" sh -lc "pg_isready -U '$DB_USER' -d '$DB_NAME'" >/dev/null

log "Criando banco de dados se necessario"
compose exec -T "$API_SERVICE" bin/rails db:create || true

log "Rodando migrations Rails incrementais"
compose exec -T "$API_SERVICE" bin/rails db:migrate
validate_critical_migrations

log "Garantindo workout_blocks para exercicios existentes"
compose exec -T "$API_SERVICE" bin/rails blocks:backfill_single_blocks
compose exec -T "$API_SERVICE" bin/rails blocks:assert_no_null_workout_blocks

log "Atualizando assets de exercicios"
compose exec -T "$API_SERVICE" bin/rails exercises:import_local_images || true
compose run --rm -v /home/easy/Easy-Health/external/free-exercise-db/exercises:/external/free-exercise-db/exercises "$API_SERVICE" bin/rails exercises:import_all || true

log "Auditando catalogo gifdotreino em modo dry-run"
compose exec -T "$API_SERVICE" bin/rails exercises:purge_non_gifdotreino DRY_RUN=1

healthcheck

log "Validando persistencia depois do deploy"
bash scripts/production/check_persistence.sh
write_snapshot "$after_snapshot"
validate_no_drop "$before_snapshot" "$after_snapshot"

printf 'DEPLOY SEGURO CONCLUIDO COM SUCESSO\n'
