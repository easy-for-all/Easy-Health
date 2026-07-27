# Views BI de Observabilidade — EasyHealth

Cinco views SQL com prefixo `bi_observability_`, consumidas pela réplica BI (`easy_health_bi`) e pelo Power BI.

Definições em `api/db/views/*.sql`, aplicadas por `Observability::BiViews`.

---

## ⚠️ `db/schema.rb` NÃO contém estas views

O `schema_format` do projeto é `:ruby`, e o dumper Ruby **não sabe representar views**. Consequência prática:

- Banco criado com `db:migrate` (produção) → tem as views.
- Banco criado com `db:schema:load` (máquina nova, CI, `db:test:prepare`) → **não tem nenhuma**.

Isso é silencioso e só aparece como um spec que passa local e falha no CI.

A lacuna é fechada aplicando as views **de forma idempotente** (`CREATE OR REPLACE`) em três lugares:

| Onde | O quê |
|---|---|
| `db/migrate/20260727120004_create_observability_bi_views.rb` | produção, via `db:migrate` |
| `spec/rails_helper.rb`, `before(:suite)` | suíte de testes |
| `.github/workflows/pr-check.yml`, job `rspec` | CI, após `db:test:prepare` |

**Depois de qualquer `db:schema:load`, rode:**

```bash
bin/rails observability:bi_views:apply
bin/rails observability:bi_views:verify   # aborta se faltar alguma
```

---

## Regras de construção

Seguidas por todas as views, e o motivo de cada uma:

| Regra | Por quê |
|---|---|
| Colunas enumeradas, nunca `SELECT *` | um `ALTER TABLE` futuro mudaria a forma da view em silêncio e pode quebrar o restore |
| Nenhuma view referencia outra | elimina qualquer risco de ordem de dependência no `pg_restore` |
| Toda taxa usa `ROUND(num::numeric / NULLIF(den, 0), 4)` | denominador vazio vira **NULL**, nunca 0 |
| Bucket de dia em `America/Sao_Paulo` | alinhado com `Analytics::ReportingTime` e com o resto do admin |
| Armazenamento em UTC | apresentação converte; a coluna crua não mente |
| Sem `SECURITY DEFINER` | as views rodam com o papel de quem consulta |

**NULL vs 0 é a regra mais importante.** Um build com duas instalações e nenhum cadastro tem conversão **desconhecida**, não 0%. Se o Power BI mostrar 0% ali, a decisão tomada em cima disso estará errada.

### Fuso fixo

Views não leem ENV. `America/Sao_Paulo` está **hardcoded** nos arquivos SQL. Se `ANALYTICS_REPORTING_TIMEZONE` mudar, é preciso criar `_v02.sql` — o applier usa sempre a maior versão de cada view.

---

## As cinco views

### `bi_observability_daily`
Uma linha por dia/ambiente: total de checks por status, incidentes abertos e resolvidos, jobs e integrações em falha. `healthy_rate` é NULL quando nenhum check rodou naquele dia.

### `bi_observability_android_build_daily`
Uma linha por dia/versão/build: instalações, autenticadas, vinculadas, cadastros iniciados/concluídos/falhos, tentativas e falhas de Google auth, taxas de conversão e vínculo.

Denominador vem de `app_installations` (base instalada real). Eventos entram só como numeradores auxiliares.

### `bi_observability_google_auth_daily`
Uma linha por dia/fluxo/plataforma/versão/build, com cada motivo de falha em coluna própria.

**`consent_required` e `consent_required_with_terms` são colunas separadas e não devem ser somadas.** A primeira inclui o caso esperado (login em conta inexistente); a segunda isola a anomalia (o cliente já tinha o consentimento e o servidor recusou).

### `bi_observability_heartbeats`
Estado atual dos processos. `calculated_status` espelha `ObservabilityHeartbeat#status`, inclusive o caso `insufficient_data` de processo recém-registrado. `seconds_since_success` é NULL quando nunca houve sucesso.

### `bi_observability_incidents`
Uma linha por incidente, com `duration_minutes` (usa `NOW()` para incidentes abertos) e `is_resolved`.

---

## Consultas de exemplo

### Builds com pior conversão de cadastro

```sql
SELECT app_version, app_build,
       SUM(installations)        AS instalacoes,
       SUM(linked_installations) AS vinculadas,
       ROUND(SUM(linked_installations)::numeric / NULLIF(SUM(installations), 0), 4) AS conversao
FROM bi_observability_android_build_daily
WHERE date >= CURRENT_DATE - 30
GROUP BY 1, 2
HAVING SUM(installations) >= 10          -- piso de amostra: sem ele o ranking é ruído
ORDER BY conversao ASC NULLS LAST
LIMIT 20;
```

### Builds com pior vínculo

```sql
SELECT app_build,
       SUM(installations) AS instalacoes,
       SUM(installations) - SUM(linked_installations) AS anonimas,
       ROUND(SUM(linked_installations)::numeric / NULLIF(SUM(installations), 0), 4) AS taxa_vinculo
FROM bi_observability_android_build_daily
WHERE date >= CURRENT_DATE - 30
  AND build_group <> 'legacy'            -- legado nunca enviou X-Installation-Id
GROUP BY 1
HAVING SUM(installations) >= 10
ORDER BY taxa_vinculo ASC NULLS LAST;
```

### Falhas do Google por dia

```sql
SELECT date, flow,
       SUM(attempts) AS tentativas,
       SUM(failures) AS falhas,
       ROUND(SUM(failures)::numeric / NULLIF(SUM(attempts), 0), 4) AS taxa_erro,
       SUM(invalid_audience) AS aud_invalida,
       SUM(consent_required_with_terms) AS anomalia_consentimento
FROM bi_observability_google_auth_daily
WHERE date >= CURRENT_DATE - 14
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

### Jobs atrasados agora

```sql
SELECT key, category, calculated_status,
       expected_interval_seconds,
       seconds_since_success,
       consecutive_failures, last_error_code
FROM bi_observability_heartbeats
WHERE calculated_status IN ('warning', 'critical')
ORDER BY seconds_since_success DESC NULLS FIRST;
```

### Incidentes críticos e tempo de resolução

```sql
SELECT check_key,
       COUNT(*) AS total,
       ROUND(AVG(duration_minutes), 1) AS media_min,
       ROUND(MAX(duration_minutes), 1) AS pior_min,
       SUM(occurrence_count) AS deteccoes
FROM bi_observability_incidents
WHERE severity = 'critical'
  AND first_detected_at >= NOW() - INTERVAL '30 days'
GROUP BY 1
ORDER BY total DESC;
```

### Comparação antes/depois de um deploy

Troque as datas pelo momento do deploy:

```sql
WITH janela AS (SELECT TIMESTAMP '2026-07-27 14:00:00' AS deploy)
SELECT
  CASE WHEN d.date < janela.deploy::date THEN 'antes' ELSE 'depois' END AS periodo,
  SUM(d.installations)  AS instalacoes,
  ROUND(SUM(d.linked_installations)::numeric / NULLIF(SUM(d.installations), 0), 4) AS conversao,
  SUM(d.google_auth_failed) AS falhas_google
FROM bi_observability_android_build_daily d, janela
WHERE d.date BETWEEN janela.deploy::date - 7 AND janela.deploy::date + 7
GROUP BY 1;
```

> Compare períodos com volume parecido. Uma "queda" medida contra um fim de semana é sazonalidade, não regressão.

---

## Verificação na réplica

`scripts/bi_replica/refresh_bi_replica.sh` confere, **após a troca**, que a réplica tem as 5 views:

```sql
SELECT count(*) FROM pg_views WHERE viewname LIKE 'bi\_observability%';
```

Se der diferente de `BI_EXPECTED_VIEW_COUNT` (padrão 5), o script falha em vez de deixar o Power BI ler uma réplica incompleta em silêncio.

As views viajam normalmente no `pg_dump`/`pg_restore` — são objetos reais do Postgres. O risco nunca esteve na réplica, e sim no lado Rails (`schema.rb`).
