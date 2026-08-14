#!/usr/bin/env bash
#
# Instala o bloco de cron gerenciado da orquestração de eventos.
#
# DRY_RUN=1 é o DEFAULT. O script mostra o diff e sai sem tocar no crontab;
# só aplica com APPLY=1. Infraestrutura de scheduler que existe apenas na
# memória de quem digitou `crontab -e` é exatamente o problema que este arquivo
# resolve, então a aplicação tem que ser um ato consciente e revisável.
#
# Garantias:
#   - tudo que está FORA dos marcadores é preservado byte a byte;
#   - reexecutar substitui o bloco, nunca duplica;
#   - a entrada legada do RelationshipDailyJob (rails runner ...) só é removida
#     com MIGRATE_RELATIONSHIP_DAILY=1 explícito — remover em silêncio poderia
#     desligar o job, e mantê-la junto com a nova o rodaria duas vezes por dia.
#
# Uso:
#   scripts/cron/install_cron.sh                          # diff, não aplica
#   APPLY=1 scripts/cron/install_cron.sh                  # aplica
#   APPLY=1 MIGRATE_RELATIONSHIP_DAILY=1 ... install_cron.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/easyhealth.cron"

APP_DIR="${APP_DIR:-/home/easy/Easy-Health}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
LOG_DIR="${LOG_DIR:-/var/log/easyhealth}"
APPLY="${APPLY:-0}"
MIGRATE_RELATIONSHIP_DAILY="${MIGRATE_RELATIONSHIP_DAILY:-0}"

BEGIN_MARKER="# >>> easyhealth-orchestration >>>"
END_MARKER="# <<< easyhealth-orchestration <<<"
# Casa com `rails runner "RelationshipDailyJob..."` / `RelationshipDailyJob.new.perform`
LEGACY_DAILY_PATTERN='RelationshipDailyJob'

log()  { printf '[easyhealth-cron] %s\n' "$*"; }
fail() { printf '[easyhealth-cron] ERRO: %s\n' "$*" >&2; exit 1; }

[ -f "$TEMPLATE" ] || fail "template nao encontrado: $TEMPLATE"

CURRENT="$(crontab -l 2>/dev/null || true)"

# Bloco novo, com as variáveis substituídas.
BLOCK="$(
  printf '%s\n' "$BEGIN_MARKER"
  sed -e "s|APP_DIR_PLACEHOLDER|$APP_DIR|g" \
      -e "s|COMPOSE_FILE_PLACEHOLDER|$COMPOSE_FILE|g" \
      -e "s|LOG_DIR_PLACEHOLDER|$LOG_DIR|g" \
      "$TEMPLATE"
  printf '%s\n' "$END_MARKER"
)"

# Remove o bloco gerenciado anterior (se houver), preservando o resto.
REMAINDER="$(printf '%s\n' "$CURRENT" | awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip   { print }
')"

# Entrada legada do daily, fora do bloco gerenciado.
LEGACY_LINES="$(printf '%s\n' "$REMAINDER" | grep -F "$LEGACY_DAILY_PATTERN" || true)"

if [ -n "$LEGACY_LINES" ]; then
  if [ "$MIGRATE_RELATIONSHIP_DAILY" = "1" ]; then
    log "Removendo a entrada legada do RelationshipDailyJob (MIGRATE_RELATIONSHIP_DAILY=1):"
    printf '%s\n' "$LEGACY_LINES" | sed 's/^/    - /'
    REMAINDER="$(printf '%s\n' "$REMAINDER" | grep -Fv "$LEGACY_DAILY_PATTERN" || true)"
  else
    log "ATENÇÃO: entrada legada do RelationshipDailyJob encontrada e MANTIDA:"
    printf '%s\n' "$LEGACY_LINES" | sed 's/^/    ! /'
    log "  Ela e 'orchestration:relationship_daily' rodariam o MESMO job duas vezes."
    log "  Revise e reaplique com MIGRATE_RELATIONSHIP_DAILY=1 para substituí-la."
  fi
fi

NEW_CRONTAB="$(
  printf '%s\n' "$REMAINDER" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba'
  printf '%s\n' "$BLOCK"
)"

TMP_CURRENT="$(mktemp)"; TMP_NEW="$(mktemp)"
trap 'rm -f "$TMP_CURRENT" "$TMP_NEW"' EXIT
printf '%s\n' "$CURRENT" > "$TMP_CURRENT"
printf '%s\n' "$NEW_CRONTAB" > "$TMP_NEW"

log "Diff do crontab (- remove, + adiciona):"
if diff -u "$TMP_CURRENT" "$TMP_NEW" | tail -n +3; then
  log "  (nenhuma mudança)"
fi

if [ "$APPLY" != "1" ]; then
  log "DRY RUN — nada foi alterado. Rode com APPLY=1 para aplicar."
  exit 0
fi

printf '%s\n' "$NEW_CRONTAB" | crontab -
log "Crontab atualizado. Bloco gerenciado ativo:"
printf '%s\n' "$BLOCK" | sed 's/^/    /'
log "Valide com: crontab -l | sed -n '/easyhealth-orchestration/,/easyhealth-orchestration/p'"
log "E, após o primeiro ciclo: rake orchestration:status"
