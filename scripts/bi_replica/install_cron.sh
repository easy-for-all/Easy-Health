#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/refresh_bi_replica.sh"
BI_REPLICA_ENV_FILE="${BI_REPLICA_ENV_FILE:-/etc/easyhealth/bi_replica.env}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"
CRON_LINE="$CRON_SCHEDULE BI_REPLICA_ENV_FILE=$BI_REPLICA_ENV_FILE $SCRIPT_PATH"

log() {
  printf '[bi-replica-cron] %s\n' "$*"
}

fail() {
  printf '[bi-replica-cron] ERRO: %s\n' "$*" >&2
  exit 1
}

[ -f "$SCRIPT_PATH" ] || fail "script nao encontrado: $SCRIPT_PATH"
[ -x "$SCRIPT_PATH" ] || fail "script sem permissao de execucao: chmod +x $SCRIPT_PATH"

(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" || true; printf '%s\n' "$CRON_LINE") | crontab -

log "Cron instalado:"
printf '%s\n' "$CRON_LINE"
