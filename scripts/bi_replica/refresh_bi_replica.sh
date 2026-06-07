#!/usr/bin/env bash
set -euo pipefail

BI_REPLICA_ENV_FILE="${BI_REPLICA_ENV_FILE:-/etc/easyhealth/bi_replica.env}"

if [ -f "$BI_REPLICA_ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a
  source "$BI_REPLICA_ENV_FILE"
  set +a
fi

BI_DB_NAME="${BI_DB_NAME:-easy_health_bi}"
BI_TMP_DB_NAME="${BI_TMP_DB_NAME:-easy_health_bi_tmp}"
BI_OLD_DB_NAME="${BI_OLD_DB_NAME:-easy_health_bi_old}"
PROD_DB_NAME="${PROD_DB_NAME:-easy_health_production}"
POWERBI_USER="${POWERBI_USER:-powerbi_readonly}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/easyhealth/bi}"
LOG_DIR="${LOG_DIR:-/var/log/easyhealth}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
DUMP_FILE="$BACKUP_DIR/easy_health_production_$TIMESTAMP.dump"
LOG_FILE="$LOG_DIR/bi_replica_$TIMESTAMP.log"

log() {
  printf '[bi-replica] %s\n' "$*" | tee -a "$LOG_FILE"
}

fail() {
  printf '[bi-replica] ERRO: %s\n' "$*" | tee -a "$LOG_FILE" >&2
  exit 1
}

require_env() {
  name="$1"
  if [ -z "${!name:-}" ]; then
    fail "$name nao definida"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "comando obrigatorio nao encontrado no PATH: $1"
}

validate_identifier() {
  value="$1"
  label="$2"
  case "$value" in
    ''|*[!a-zA-Z0-9_]*)
      fail "$label invalido: use apenas letras, numeros e underscore"
      ;;
  esac
}

sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

psql_admin() {
  psql "$POSTGRES_ADMIN_URL" -v ON_ERROR_STOP=1 "$@"
}

psql_bi_final() {
  psql "$BI_DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
}

psql_bi_tmp() {
  psql "$BI_TMP_DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
}

run_logged() {
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

run_psql_admin() {
  set +e
  psql "$POSTGRES_ADMIN_URL" -v ON_ERROR_STOP=1 "$@" 2>&1 | tee -a "$LOG_FILE"
  status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

run_psql_bi_final() {
  set +e
  psql "$BI_DATABASE_URL" -v ON_ERROR_STOP=1 "$@" 2>&1 | tee -a "$LOG_FILE"
  status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

run_psql_bi_tmp() {
  set +e
  psql "$BI_TMP_DATABASE_URL" -v ON_ERROR_STOP=1 "$@" 2>&1 | tee -a "$LOG_FILE"
  status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

cleanup_tmp() {
  if [ "${created_tmp:-0}" = "1" ]; then
    log "Limpando banco temporario apos falha, se existir"
    run_psql_admin <<SQL || true
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$BI_TMP_DB_NAME_SQL';

DROP DATABASE IF EXISTS "$BI_TMP_DB_NAME";
SQL
  fi
}

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
chmod 700 "$BACKUP_DIR" "$LOG_DIR" 2>/dev/null || true
touch "$LOG_FILE"
chmod 600 "$LOG_FILE" 2>/dev/null || true

log "Iniciando replica BI da EasyHealth"
log "Dump: $DUMP_FILE"
log "Log: $LOG_FILE"

require_env PROD_DATABASE_URL
require_env POSTGRES_ADMIN_URL
require_env BI_DATABASE_URL
require_env BI_TMP_DATABASE_URL

validate_identifier "$BI_DB_NAME" BI_DB_NAME
validate_identifier "$BI_TMP_DB_NAME" BI_TMP_DB_NAME
validate_identifier "$BI_OLD_DB_NAME" BI_OLD_DB_NAME
validate_identifier "$PROD_DB_NAME" PROD_DB_NAME
validate_identifier "$POWERBI_USER" POWERBI_USER

case "$RETENTION_DAYS" in
  ''|*[!0-9]*)
    fail "RETENTION_DAYS precisa ser um numero inteiro nao negativo"
    ;;
esac

require_command pg_dump
require_command pg_restore
require_command psql

if [ "$BI_DB_NAME" = "$PROD_DB_NAME" ] || [ "$BI_TMP_DB_NAME" = "$PROD_DB_NAME" ] || [ "$BI_OLD_DB_NAME" = "$PROD_DB_NAME" ]; then
  fail "nomes de banco BI nao podem ser iguais ao banco de producao ($PROD_DB_NAME)"
fi

if [ "$BI_DB_NAME" = "$BI_TMP_DB_NAME" ] || [ "$BI_DB_NAME" = "$BI_OLD_DB_NAME" ] || [ "$BI_TMP_DB_NAME" = "$BI_OLD_DB_NAME" ]; then
  fail "BI_DB_NAME, BI_TMP_DB_NAME e BI_OLD_DB_NAME precisam ser diferentes"
fi

BI_DB_NAME_SQL="$(sql_literal "$BI_DB_NAME")"
BI_TMP_DB_NAME_SQL="$(sql_literal "$BI_TMP_DB_NAME")"
BI_OLD_DB_NAME_SQL="$(sql_literal "$BI_OLD_DB_NAME")"
POWERBI_USER_SQL="$(sql_literal "$POWERBI_USER")"

created_tmp=0
trap cleanup_tmp EXIT

log "Banco BI final: $BI_DB_NAME"
log "Banco temporario: $BI_TMP_DB_NAME"

log "Gerando dump da producao"
run_logged pg_dump "$PROD_DATABASE_URL" \
  --format=custom \
  --blobs \
  --no-owner \
  --no-acl \
  --file="$DUMP_FILE" || fail "pg_dump falhou"

[ -s "$DUMP_FILE" ] || fail "dump nao foi criado ou esta vazio: $DUMP_FILE"
chmod 600 "$DUMP_FILE" 2>/dev/null || true

log "Recriando banco temporario"
created_tmp=1
run_psql_admin <<SQL || fail "falha ao recriar banco temporario"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$BI_TMP_DB_NAME_SQL';

DROP DATABASE IF EXISTS "$BI_TMP_DB_NAME";
CREATE DATABASE "$BI_TMP_DB_NAME";
SQL

log "Restaurando dump no banco temporario"
run_logged pg_restore \
  --dbname="$BI_TMP_DATABASE_URL" \
  --no-owner \
  --no-acl \
  --clean \
  --if-exists \
  "$DUMP_FILE" || fail "pg_restore falhou"

log "Validando restore"
TABLE_COUNT="$(psql_bi_tmp -Atc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)"

if [ -z "$TABLE_COUNT" ] || [ "$TABLE_COUNT" -lt 1 ]; then
  fail "restore aparentemente invalido. Nenhuma tabela encontrada"
fi

log "Restore validado. Tabelas encontradas: $TABLE_COUNT"

log "Validando role read-only"
ROLE_EXISTS="$(psql_admin -Atc "SELECT COUNT(*) FROM pg_roles WHERE rolname = '$POWERBI_USER_SQL';" | xargs)"

if [ "$ROLE_EXISTS" != "1" ]; then
  fail "role $POWERBI_USER nao existe. Execute create_bi_user.sql antes do refresh"
fi

log "Aplicando permissoes read-only no banco temporario"
run_psql_bi_tmp <<SQL || fail "falha ao aplicar permissoes no banco temporario"
GRANT CONNECT ON DATABASE "$BI_TMP_DB_NAME" TO "$POWERBI_USER";
GRANT USAGE ON SCHEMA public TO "$POWERBI_USER";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "$POWERBI_USER";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO "$POWERBI_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "$POWERBI_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO "$POWERBI_USER";
SQL

log "Trocando banco BI final com fallback"
run_psql_admin <<SQL || fail "falha ao promover banco temporario para BI final"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname IN ('$BI_DB_NAME_SQL', '$BI_TMP_DB_NAME_SQL', '$BI_OLD_DB_NAME_SQL');

DROP DATABASE IF EXISTS "$BI_OLD_DB_NAME";

SELECT format('ALTER DATABASE %I RENAME TO %I', '$BI_DB_NAME_SQL', '$BI_OLD_DB_NAME_SQL')
WHERE EXISTS (
  SELECT 1
  FROM pg_database
  WHERE datname = '$BI_DB_NAME_SQL'
)
\gexec

ALTER DATABASE "$BI_TMP_DB_NAME" RENAME TO "$BI_DB_NAME";
SQL
created_tmp=0

log "Confirmando CONNECT read-only no banco final"
run_psql_bi_final <<SQL || fail "falha ao confirmar permissao CONNECT no banco final"
GRANT CONNECT ON DATABASE "$BI_DB_NAME" TO "$POWERBI_USER";
SQL

log "Removendo banco BI antigo"
run_psql_admin <<SQL || fail "falha ao remover banco BI antigo"
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$BI_OLD_DB_NAME_SQL';

DROP DATABASE IF EXISTS "$BI_OLD_DB_NAME";
SQL

log "Limpando dumps antigos, mantendo ultimos $RETENTION_DAYS dias"
find "$BACKUP_DIR" -type f -name "*.dump" -mtime +"$RETENTION_DAYS" -delete

trap - EXIT
log "Replica BI concluida com sucesso"
