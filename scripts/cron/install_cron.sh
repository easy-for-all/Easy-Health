#!/usr/bin/env bash
#
# Instala o bloco de cron gerenciado da orquestração de comunicações.
#
# DRY RUN é o default. Aplique com APPLY=1 depois de revisar o diff.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/easyhealth.cron"

APP_DIR="${APP_DIR:-/home/easy/Easy-Health}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
API_SERVICE="${API_SERVICE:-api}"
LOG_DIR="${LOG_DIR:-logs}"
APPLY="${APPLY:-0}"
SKIP_RUNTIME_VALIDATION="${SKIP_RUNTIME_VALIDATION:-0}"
CRON_TZ_MODE="${CRON_TZ_MODE:-auto}"

BEGIN_MARKER="# BEGIN EASYHEALTH ORCHESTRATION"
END_MARKER="# END EASYHEALTH ORCHESTRATION"

log()  { printf '[easyhealth-cron] %s\n' "$*"; }
fail() { printf '[easyhealth-cron] ERRO: %s\n' "$*" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "template nao encontrado: $TEMPLATE"

log_path() {
  case "$LOG_DIR" in
    /*) printf '%s\n' "$LOG_DIR" ;;
    *) printf '%s/%s\n' "$APP_DIR" "$LOG_DIR" ;;
  esac
}

validate_runtime() {
  [ "$APPLY" = "1" ] || return 0
  [ "$SKIP_RUNTIME_VALIDATION" = "1" ] && return 0

  [ -d "$APP_DIR" ] || fail "APP_DIR nao existe: $APP_DIR"
  [ -f "$APP_DIR/$COMPOSE_FILE" ] || fail "compose nao encontrado: $APP_DIR/$COMPOSE_FILE"

  if ! docker compose -f "$APP_DIR/$COMPOSE_FILE" ps -q "$API_SERVICE" >/dev/null 2>&1; then
    fail "nao foi possivel consultar docker compose para service=$API_SERVICE"
  fi

  api_container="$(docker compose -f "$APP_DIR/$COMPOSE_FILE" ps -q "$API_SERVICE")"
  [ -n "$api_container" ] || fail "container esperado nao encontrado para service=$API_SERVICE"
}

flock_prefix() {
  lock="$1"
  if command -v flock >/dev/null 2>&1; then
    printf 'flock -n %s' "$lock"
  else
    log "flock nao encontrado; cron dependera da idempotencia do scheduler ($lock)"
    printf ''
  fi
}

cron_tz_supported() {
  case "$CRON_TZ_MODE" in
    force) return 0 ;;
    utc_fallback) return 1 ;;
  esac

  if command -v man >/dev/null 2>&1 && man 5 crontab 2>/dev/null | grep -q 'CRON_TZ'; then
    return 0
  fi

  if crontab -V 2>/dev/null | grep -Eqi 'cronie|vixie|isc'; then
    return 0
  fi

  return 1
}

if cron_tz_supported; then
  CRON_TZ_LINE="CRON_TZ=America/Sao_Paulo"
  DAILY_CRON="0 8 * * *"
else
  CRON_TZ_LINE="# CRON_TZ=America/Sao_Paulo nao detectado neste cron; fallback tecnico em UTC."
  DAILY_CRON="0 11 * * *"
  log "CRON_TZ nao detectado; daily sera instalado como 11:00 UTC (= 08:00 America/Sao_Paulo)."
fi

FLOCK_DAILY="$(flock_prefix /tmp/easyhealth-relationship-daily.lock)"
FLOCK_15MIN="$(flock_prefix /tmp/easyhealth-orchestration-15min.lock)"
FLOCK_MAKE_RETRY="$(flock_prefix /tmp/easyhealth-make-pending-retry.lock)"
FLOCK_DEFERRED="$(flock_prefix /tmp/easyhealth-push-dispatch-deferred.lock)"

CURRENT="$(crontab -l 2>/dev/null || true)"

BLOCK="$(
  printf '%s\n' "$BEGIN_MARKER"
  sed -e "s|APP_DIR_PLACEHOLDER|$APP_DIR|g" \
      -e "s|COMPOSE_FILE_PLACEHOLDER|$COMPOSE_FILE|g" \
      -e "s|API_SERVICE_PLACEHOLDER|$API_SERVICE|g" \
      -e "s|LOG_DIR_PLACEHOLDER|$LOG_DIR|g" \
      -e "s|CRON_TZ_LINE_PLACEHOLDER|$CRON_TZ_LINE|g" \
      -e "s|DAILY_CRON_PLACEHOLDER|$DAILY_CRON|g" \
      -e "s|FLOCK_DAILY_PLACEHOLDER|$FLOCK_DAILY|g" \
      -e "s|FLOCK_15MIN_PLACEHOLDER|$FLOCK_15MIN|g" \
      -e "s|FLOCK_MAKE_RETRY_PLACEHOLDER|$FLOCK_MAKE_RETRY|g" \
      -e "s|FLOCK_DEFERRED_PLACEHOLDER|$FLOCK_DEFERRED|g" \
      "$TEMPLATE"
  printf '%s\n' "$END_MARKER"
)"

REMAINDER="$(printf '%s\n' "$CURRENT" | awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip   { print }
')"

LEGACY_LINES="$(printf '%s\n' "$REMAINDER" | awk '
  /RelationshipDailyJob\.new\.perform/ { print; next }
  /orchestration:relationship_daily/ { print; next }
  /orchestration:run_15min/ { print; next }
  /scheduled_workout_reminders:run/ { print; next }
  /MakeWebhookClient\.new\.deliver/ && /make_delivery_status/ && /pending/ { print; next }
')"

if [ -n "$LEGACY_LINES" ]; then
  log "Removendo linhas legacy EasyHealth reconhecidas:"
  printf '%s\n' "$LEGACY_LINES" | sed 's/^/    - /'
  REMAINDER="$(printf '%s\n' "$REMAINDER" | awk '
    /RelationshipDailyJob\.new\.perform/ { next }
    /orchestration:relationship_daily/ { next }
    /orchestration:run_15min/ { next }
    /scheduled_workout_reminders:run/ { next }
    /MakeWebhookClient\.new\.deliver/ && /make_delivery_status/ && /pending/ { next }
    { print }
  ')"
fi

NEW_CRONTAB="$(
  printf '%s\n' "$REMAINDER" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba'
  printf '%s\n' "$BLOCK"
)"

TMP_CURRENT="$(mktemp)"
TMP_NEW="$(mktemp)"
trap 'rm -f "$TMP_CURRENT" "$TMP_NEW"' EXIT
printf '%s\n' "$CURRENT" > "$TMP_CURRENT"
printf '%s\n' "$NEW_CRONTAB" > "$TMP_NEW"

grep -qF "$BEGIN_MARKER" "$TMP_NEW" || fail "bloco gerenciado sem marcador inicial"
grep -qF "$END_MARKER" "$TMP_NEW" || fail "bloco gerenciado sem marcador final"

log "Diff do crontab (- remove, + adiciona):"
if diff -u "$TMP_CURRENT" "$TMP_NEW" | tail -n +3; then
  log "  (nenhuma mudança)"
fi

if [ "$APPLY" != "1" ]; then
  log "DRY RUN — nada foi alterado. Rode com APPLY=1 para aplicar."
  exit 0
fi

validate_runtime
mkdir -p "$(log_path)"

crontab "$TMP_NEW"
log "Crontab atualizado. Bloco gerenciado ativo:"
printf '%s\n' "$BLOCK" | sed 's/^/    /'
log "Valide com: crontab -l | sed -n '/BEGIN EASYHEALTH ORCHESTRATION/,/END EASYHEALTH ORCHESTRATION/p'"
log "E, após o primeiro ciclo: docker compose -f $COMPOSE_FILE exec -T $API_SERVICE bin/rails orchestration:status"
