#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
API_SERVICE="${API_SERVICE:-api}"
WEB_SERVICE="${WEB_SERVICE:-web}"
DB_NAME="${DB_NAME:-easy_health_production}"
DB_USER="${DB_USER:-${DB_USERNAME:-postgres}}"
TARGET_REF="${1:-${GIT_COMMIT:-origin/main}}"
# /api/v1/health e não /up: o endpoint do Rails responde 200 com o processo de
# pé e o banco inacessível, que é exatamente o estado que este deploy precisa
# saber distinguir. Interno, antes do Cloudflare: um 502 do Cloudflare e uma API
# morta se parecem, e só um deles é problema nosso.
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://localhost:3001/api/v1/health}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-60}"

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
  for version in 20260706130000 20260709020100 20260709020102 20260709152000 \
                 20260715120000 20260715120001 20260715120002 20260715120003; do
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

assert_web_client_id() {
  log "Validando NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID no .env"
  local val
  val="$(grep -E '^NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID=' .env 2>/dev/null | head -1 | cut -d= -f2-)"
  [ -n "$val" ] || fail "NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID ausente/vazia no .env de producao"
  case "$val" in
    *.apps.googleusercontent.com) log "NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID present: yes (ends with .apps.googleusercontent.com)";;
    *) fail "NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID com formato inesperado (esperado terminar em .apps.googleusercontent.com)";;
  esac
}

# Exige 200 E db:true. "Container running" não é deploy bem sucedido: o
# incidente de 04/08 teve container de pé o tempo todo — o que estava morto era
# o Rails atrás dele, e o Cloudflare traduzia isso em 502 para o usuário.
healthcheck() {
  log "Rodando healthcheck em $HEALTHCHECK_URL (ate ${HEALTHCHECK_TIMEOUT}s)"
  body_file="$(mktemp)"
  deadline=$((SECONDS + HEALTHCHECK_TIMEOUT))
  last_status="nenhuma resposta"

  while [ "$SECONDS" -lt "$deadline" ]; do
    http_code="$(curl -sS -m 5 -o "$body_file" -w '%{http_code}' "$HEALTHCHECK_URL" 2>/dev/null || echo "000")"

    if [ "$http_code" = "200" ] && grep -q '"db":true' "$body_file"; then
      log "Healthcheck OK (HTTP 200, db acessivel)"
      rm -f "$body_file"
      return
    fi

    last_status="HTTP $http_code"
    log "Healthcheck ainda nao passou ($last_status); aguardando"
    sleep 5
  done

  log "Ultima resposta do healthcheck:"
  cat "$body_file" || true
  rm -f "$body_file"
  show_new_api_logs
  fail "healthcheck falhou apos ${HEALTHCHECK_TIMEOUT}s (ultimo: $last_status)"
}

# Só o que o container NOVO escreveu. Depois do incidente, metade do tempo de
# diagnóstico foi gasto lendo stack trace do container anterior e concluindo a
# coisa errada; a janela é fixada antes do up justamente para não haver dúvida.
show_new_api_logs() {
  [ -n "${DEPLOY_STARTED_AT:-}" ] || return 0
  log "Logs da API desde $DEPLOY_STARTED_AT"
  compose logs --since "$DEPLOY_STARTED_AT" --tail 200 "$API_SERVICE" || true
}

# O portão. Migrations rodam num container efêmero da imagem NOVA, com a API
# antiga ainda no ar e atendendo. Se falharem, o deploy morre aqui e produção
# continua exatamente como estava — que é o oposto do que aconteceu em 04/08,
# quando a migration só foi descoberta no boot do container que já havia
# substituído o que funcionava.
run_migration_gate() {
  log "Migration gate: rodando migrations em container one-off da imagem nova"

  compose run --rm -T "$API_SERVICE" bin/rails db:create || true

  if ! compose run --rm -T "$API_SERVICE" bin/rails db:migrate; then
    printf '\n' >&2
    printf 'DEPLOY ABORTED: database migration failed.\n' >&2
    printf 'Existing production containers were not replaced.\n' >&2
    printf '\n' >&2
    exit 1
  fi

  validate_critical_migrations

  # Dados que a aplicação nova pressupõe. Mesma regra do migrate: se o banco não
  # consegue ficar no formato que o código novo espera, a API que está no ar não
  # é substituída para descobrir isso em produção.
  if ! compose run --rm -T "$API_SERVICE" bin/rails blocks:backfill_single_blocks; then
    printf 'DEPLOY ABORTED: workout block backfill failed.\n' >&2
    printf 'Existing production containers were not replaced.\n' >&2
    exit 1
  fi

  if ! compose run --rm -T "$API_SERVICE" bin/rails blocks:assert_no_null_workout_blocks; then
    printf 'DEPLOY ABORTED: workout block invariant check failed.\n' >&2
    printf 'Existing production containers were not replaced.\n' >&2
    exit 1
  fi

  log "Migration gate OK; liberado para substituir os containers"
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

assert_web_client_id

copy_exercise_images

# Build SEM recriar nada. A API que está no ar continua servindo enquanto a
# imagem nova é construída e enquanto as migrations são validadas contra ela.
log "Construindo imagens novas (containers atuais seguem no ar)"
compose build

log "Garantindo que o banco esta de pe para o migration gate"
compose up -d "$DB_SERVICE"
compose exec -T "$DB_SERVICE" sh -lc "pg_isready -U '$DB_USER' -d '$DB_NAME'" >/dev/null

run_migration_gate

# Só aqui os containers são substituídos, e só porque o banco já está no
# formato que a imagem nova espera.
DEPLOY_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "Migrations aplicadas; subindo containers novos sem apagar volumes"
compose up -d

log "Limpando cache de build do Docker (evita esgotar disco em deploys futuros)"
docker builder prune -af || true
docker image prune -af || true

log "Aguardando API"
sleep 10

# Antes dos assets: importar catálogo por vários minutos contra uma API que não
# subiu só atrasa a descoberta de que ela não subiu.
healthcheck

log "Atualizando assets de exercicios"
compose exec -T "$API_SERVICE" bin/rails exercises:import_local_images || true
compose run --rm -v /home/easy/Easy-Health/external/free-exercise-db/exercises:/external/free-exercise-db/exercises "$API_SERVICE" bin/rails exercises:import_all || true

log "Auditando catalogo gifdotreino em modo dry-run"
compose exec -T "$API_SERVICE" bin/rails exercises:purge_non_gifdotreino DRY_RUN=1

log "Validando persistencia depois do deploy"
bash scripts/production/check_persistence.sh
write_snapshot "$after_snapshot"
validate_no_drop "$before_snapshot" "$after_snapshot"

show_new_api_logs

printf 'DEPLOY SEGURO CONCLUIDO COM SUCESSO\n'
