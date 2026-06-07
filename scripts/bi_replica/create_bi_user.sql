\set ON_ERROR_STOP on

-- Prepare o banco BI e o usuario read-only para Power BI.
-- Uso recomendado:
--   psql "$POSTGRES_ADMIN_URL" \
--     -v bi_db_name=easy_health_bi \
--     -v powerbi_user=powerbi_readonly \
--     -v powerbi_password="$POWERBI_READONLY_PASSWORD" \
--     -f scripts/bi_replica/create_bi_user.sql

\if :{?bi_db_name}
\else
  \set bi_db_name easy_health_bi
\endif

\if :{?powerbi_user}
\else
  \set powerbi_user powerbi_readonly
\endif

\if :{?powerbi_password}
\else
  \echo 'ERRO: defina powerbi_password via -v powerbi_password="$POWERBI_READONLY_PASSWORD"'
  \quit 1
\endif

SELECT format('CREATE DATABASE %I', :'bi_db_name')
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_database
  WHERE datname = :'bi_db_name'
)
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'powerbi_user', :'powerbi_password')
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = :'powerbi_user'
)
\gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'powerbi_user', :'powerbi_password')
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'bi_db_name', :'powerbi_user')
\gexec

\connect :bi_db_name

SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'powerbi_user')
\gexec

SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA public TO %I', :'powerbi_user')
\gexec

SELECT format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', :'powerbi_user')
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO %I', :'powerbi_user')
\gexec

SELECT format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO %I', :'powerbi_user')
\gexec
