# Replica BI para Power BI

Este fluxo cria uma copia diaria do PostgreSQL de producao em um banco separado para BI. O Power BI deve conectar apenas no banco `easy_health_bi`, com o usuario `powerbi_readonly`, em modo Import.

## Arquitetura

```txt
easy_health_production
  -> pg_dump
  -> easy_health_bi_tmp
  -> validacao
  -> easy_health_bi
  -> powerbi_readonly
  -> Power BI
```

O script nunca deve usar credenciais da aplicacao Rails no Power BI e nunca deve recriar ou apagar `easy_health_production`.

## Variaveis de ambiente

Crie um arquivo de ambiente na VPS, fora do repositorio:

```bash
sudo mkdir -p /etc/easyhealth
sudo nano /etc/easyhealth/bi_replica.env
sudo chown "$USER":"$USER" /etc/easyhealth/bi_replica.env
sudo chmod 600 /etc/easyhealth/bi_replica.env
```

O arquivo deve ser legivel pelo mesmo usuario que executa o cron.

Exemplo:

```bash
PROD_DATABASE_URL="postgres://usuario_dump:senha@host-producao:5432/easy_health_production"
POSTGRES_ADMIN_URL="postgres://postgres:senha_admin@localhost:5432/postgres"
BI_TMP_DATABASE_URL="postgres://postgres:senha_admin@localhost:5432/easy_health_bi_tmp"
BI_DATABASE_URL="postgres://postgres:senha_admin@localhost:5432/easy_health_bi"
POWERBI_READONLY_PASSWORD="troque_por_uma_senha_forte"

BI_DB_NAME="easy_health_bi"
BI_TMP_DB_NAME="easy_health_bi_tmp"
BI_OLD_DB_NAME="easy_health_bi_old"
PROD_DB_NAME="easy_health_production"
POWERBI_USER="powerbi_readonly"
BACKUP_DIR="/var/backups/easyhealth/bi"
LOG_DIR="/var/log/easyhealth"
RETENTION_DAYS="7"
```

`BI_TMP_DATABASE_URL` deve apontar para o banco temporario definido em `BI_TMP_DB_NAME`, porque o restore acontece primeiro nele. `BI_DATABASE_URL` deve apontar para o banco final definido em `BI_DB_NAME`, usado depois da troca para aplicar permissoes e validar acesso operacional.

## Criar usuario read-only

Execute uma vez no servidor:

```bash
set -a
source /etc/easyhealth/bi_replica.env
set +a

psql "$POSTGRES_ADMIN_URL" \
  -v bi_db_name="${BI_DB_NAME:-easy_health_bi}" \
  -v powerbi_user="${POWERBI_USER:-powerbi_readonly}" \
  -v powerbi_password="$POWERBI_READONLY_PASSWORD" \
  -f scripts/bi_replica/create_bi_user.sql
```

O SQL nao guarda senha no repositorio. A senha vem da variavel `POWERBI_READONLY_PASSWORD`.

## Rodar manualmente

```bash
chmod +x scripts/bi_replica/refresh_bi_replica.sh
BI_REPLICA_ENV_FILE=/etc/easyhealth/bi_replica.env scripts/bi_replica/refresh_bi_replica.sh
```

O script:

- gera dump custom do banco de producao;
- recria `easy_health_bi_tmp`;
- restaura e valida se ha tabelas;
- renomeia `easy_health_bi` antigo para `easy_health_bi_old`;
- renomeia `easy_health_bi_tmp` para `easy_health_bi`;
- reaplica grants somente leitura;
- remove o banco antigo apenas depois de concluir a troca;
- grava logs em `LOG_DIR`.

Se o dump ou restore falhar, o banco BI atual nao e substituido.

## Instalar cron diario

```bash
chmod +x scripts/bi_replica/install_cron.sh
BI_REPLICA_ENV_FILE=/etc/easyhealth/bi_replica.env scripts/bi_replica/install_cron.sh
```

Por padrao, o cron roda todos os dias as 02:00:

```txt
0 2 * * *
```

Para mudar o horario:

```bash
CRON_SCHEDULE="30 3 * * *" BI_REPLICA_ENV_FILE=/etc/easyhealth/bi_replica.env scripts/bi_replica/install_cron.sh
```

Verifique:

```bash
crontab -l
```

## Conectar no Power BI

Use:

```txt
Host: IP ou dominio do PostgreSQL BI
Database: easy_health_bi
User: powerbi_readonly
Password: senha de POWERBI_READONLY_PASSWORD
Mode: Import
```

Prefira Import em vez de DirectQuery para reduzir carga no banco BI.

## Validacoes recomendadas

Depois do primeiro refresh:

```bash
psql "postgres://powerbi_readonly:SENHA@host:5432/easy_health_bi" -c "SELECT COUNT(*) FROM users;"
psql "postgres://powerbi_readonly:SENHA@host:5432/easy_health_bi" -c "CREATE TABLE teste_powerbi(id int);"
```

O `SELECT` deve funcionar. O `CREATE TABLE` deve falhar por falta de permissao.

Tambem confirme:

- `easy_health_bi` existe;
- `powerbi_readonly` nao consegue `INSERT`, `UPDATE`, `DELETE`, `CREATE` ou `DROP`;
- logs aparecem em `/var/log/easyhealth`;
- dumps aparecem em `/var/backups/easyhealth/bi`;
- Power BI nao usa usuario da aplicacao Rails;
- `easy_health_production` nao foi alterado.

## Docker, VPS e rede

Se o PostgreSQL estiver em Docker, valide:

- container correto do PostgreSQL;
- porta BI exposta apenas quando necessario;
- firewall liberando somente IPs confiaveis;
- SSL habilitado quando possivel;
- producao sem acesso direto pela internet.

Melhor pratica: usar uma instancia PostgreSQL separada para BI. Para primeira fase, pode ser a mesma VPS, desde que exista banco separado, usuario separado, senha forte e firewall restrito.
