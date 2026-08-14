# Runbook de Observabilidade — EasyHealth

Cada cenário: como confirmar, onde olhar, SQL útil, logs úteis, ação inicial e quando resolver o incidente.

**Primeiro passo, sempre:** abrir `/admin/observability` e ler o card correspondente. O card já traz valor, amostra, threshold e a explicação da decisão.

## Cron necessário

Não instalado automaticamente. Adicionar na VPS com `crontab -e`:

```
*/15 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.prod.yml exec -T api bundle exec rake observability:check
```

Opcionalmente, para reprocessar entregas Make perdidas em restart:

```
*/30 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.prod.yml exec -T api bundle exec rake make_webhook:retry_pending
```

E limpeza diária (retenção de check results + incidentes órfãos):

```
30 4 * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.prod.yml exec -T api bundle exec rake observability:resolve_stale
```

Confira o cron existente da réplica BI com `crontab -l` e mantenha `BI_REPLICA_EXPECTED_HOUR` coerente com ele.

### Bloco gerenciado da orquestração de eventos

As rotinas acima continuam manuais. Os produtores de evento de orquestração
(lembretes 2h/24h, horário preferido e jornada diária) vivem em um bloco
**versionado**, instalado por script e delimitado por
`# >>> easyhealth-orchestration >>>`:

```bash
scripts/cron/install_cron.sh          # DRY RUN (default): mostra o diff, não aplica
APPLY=1 scripts/cron/install_cron.sh  # aplica
```

O script preserva byte a byte tudo que está fora dos marcadores. Se o diff
mostrar a entrada legada `rails runner "RelationshipDailyJob..."`, substitua-a
com `MIGRATE_RELATIONSHIP_DAILY=1` — mantê-la junto com
`orchestration:relationship_daily` rodaria o mesmo job duas vezes por dia.

Saúde desses schedulers: heartbeats `first_workout_not_started_2h`,
`first_workout_not_started_24h`, `scheduled_workout_reminder` e
`relationship_daily_job`, visíveis em `/admin/events-communications` e via
`rake orchestration:status`. Detalhes em `docs/event-orchestration.md`.

---

## 1. Cadastro Android caiu

**Confirmar:** card **Cadastro Android** amarelo/vermelho; tabela *Android por build* mostra qual build.

**Cuidado:** se o card estiver cinza, não caiu — não foi medido. Verifique a amostra antes de investigar.

**SQL:**
```sql
-- conversão por build, últimos 7 dias
SELECT date, app_version, app_build, installations, linked_installations,
       registration_conversion_rate
FROM bi_observability_android_build_daily
WHERE date >= CURRENT_DATE - 7
ORDER BY date DESC, installations DESC;
```

**Logs:**
```bash
docker compose -f docker-compose.prod.yml logs api --since 6h \
  | grep -o '{"ts".*' | jq -c 'select(.event | startswith("android_registration"))'
```

**Ação inicial:**
1. É um build específico? Compare a conversão dele com a do build anterior.
2. Se sim, cruze com o card **Login Google** — a causa mais comum é falha de autenticação, não do cadastro em si.
3. Se todos os builds caíram junto, olhe **API & Infraestrutura** e o Sentry.
4. Se só a coorte `legacy` está ruim: **isso é esperado**, esses builds nunca enviaram `X-Installation-Id`.

**Resolver o incidente quando:** a conversão voltar acima do threshold com amostra suficiente. O check resolve sozinho no ciclo seguinte.

---

## 2. Instalações não estão vinculando

**Confirmar:** card **Vínculo Android**. O sub-check `authenticated_without_installation_link` é o sinal forte.

**SQL:**
```sql
-- o estado impossível: autenticado, sem usuário
SELECT installation_id, app_version, app_build, last_authenticated_at, created_at
FROM app_installations
WHERE user_id IS NULL
  AND last_authenticated_at IS NOT NULL
  AND last_authenticated_at < NOW() - INTERVAL '5 minutes'
ORDER BY last_authenticated_at DESC
LIMIT 50;
```

**Logs:**
```bash
docker compose -f docker-compose.prod.yml logs api --since 2h \
  | grep -o '{"ts".*' | jq -c 'select(.event == "installation_link_failed")'
```

Olhe `link_result`: `not_found` (o cliente tem um id que o servidor nunca viu → o register falhou), `conflict` (a instalação pertence a outro usuário), `error` (exceção).

**Ação inicial:**
1. `not_found` predominante → investigar `POST /api/v1/app/installations/register`.
2. `conflict` predominante → aparelho compartilhado ou reinstalação; normalmente não é bug.
3. Qualquer linha no SQL acima → bug real na reconciliação. Use a busca de investigação do painel com o `installation_id`.

**Resolver quando:** a query acima voltar zero e a taxa de vínculo normalizar.

---

## 3. Google Native começou a falhar

**Confirmar:** card **Login Google**, linha com `auth_flow=native`. Ver `top_error_code`.

**SQL:**
```sql
SELECT date, flow, app_build, attempts, failures, error_rate,
       invalid_token, invalid_audience, provider_error,
       consent_required, consent_required_with_terms
FROM bi_observability_google_auth_daily
WHERE date >= CURRENT_DATE - 3 AND flow = 'native'
ORDER BY date DESC, attempts DESC;
```

**Interpretação por código:**

| Código | Causa provável | Ação |
|---|---|---|
| `invalid_audience` | `GOOGLE_ANDROID_CLIENT_ID` errado ou ausente | conferir env do servidor e o client id do build |
| `invalid_token` | token expirado ou relógio do device | se disperso entre usuários, normal; se em massa, investigar |
| `provider_error` | erro do lado do Google | verificar status do Google, aguardar |
| `consent_required` **com** `terms_accepted` | **bug nosso** — ver cenário abaixo |
| `internal_error` | exceção no servidor | Sentry, filtrando pela tag `auth_flow=native` |

**Anomalia de consentimento:** `consent_required_with_terms > 0` significa que o cliente coletou os termos e o servidor recusou mesmo assim. Verifique se o app está enviando `terms_accepted`/`privacy_accepted` no corpo e se `User.required_consent_given?` concorda com eles.

**Resolver quando:** a taxa de erro do fluxo voltar abaixo de 10% com pelo menos 10 tentativas.

---

## 4. OAuth Web começou a falhar

Mesma investigação do cenário 3, com `flow = 'web'` (ou `web_mobile` para o fluxo do Custom Tab no Android).

**Específico do web:**
- `provider_error` em massa geralmente vem do callback de falha do OmniAuth. Cheque `FRONTEND_URL` e as URIs de redirect autorizadas no Google Cloud Console.
- Se `web_mobile` falha e `web` não: o problema está no fluxo do `MobileAuthCode`, não no OAuth.

```bash
docker compose -f docker-compose.prod.yml logs api --since 2h | grep GoogleOAuth
```

---

## 5. Make parou

**Confirmar:** card **Jobs e Integrações**; sub-checks `make_delivery_backlog` e `stale_heartbeat:make_webhook_delivery`.

**SQL:**
```sql
SELECT make_delivery_status, COUNT(*),
       MIN(created_at) AS mais_antigo
FROM user_events
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY 1 ORDER BY 2 DESC;
```

**Ação inicial:**
1. Confirme a configuração: `rake make_webhook:config`.
2. Backlog acumulado após um deploy é **esperado** (adapter `:async` perde a fila). Reprocesse:
   ```bash
   docker compose -f docker-compose.prod.yml exec -T api bundle exec rake make_webhook:retry_pending
   ```
3. Se as entregas voltam a falhar depois do retry, o problema é o endpoint do Make. Veja `make_last_error` em `user_events`.

**Resolver quando:** o backlog voltar abaixo de 10 e o heartbeat `make_webhook_delivery` registrar sucesso.

---

## 6. Stripe webhook parou

**Confirmar:** sub-check `stripe_webhook_failure`.

**SQL:**
```sql
SELECT status, COUNT(*), MAX(processed_at) AS ultimo
FROM stripe_events
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY 1;
```

**Logs:**
```bash
docker compose -f docker-compose.prod.yml logs api --since 6h | grep '\[Stripe\]'
```

**Ação inicial:**
1. `signature verification failed` → `STRIPE_WEBHOOK_SECRET` divergente do endpoint configurado no Stripe. Compare com o painel do Stripe.
2. Nenhum evento chegando → confira o endpoint no dashboard do Stripe (entregas e tentativas).
3. Erro interno → Sentry.

> Falha de assinatura **não** abre incidente por si só — é um chamador rejeitado, não um pipeline quebrado.

**Resolver quando:** não houver eventos não processados na última hora.

---

## 7. Réplica não atualizou

**Confirmar:** sub-check `replica_refresh_stale`; tabela *Heartbeats*, linha `bi_replica_refresh`.

**Antes de tudo, confira o horário real:**
```bash
crontab -l | grep refresh_bi_replica
```
Se o cron não roda no horário que `BI_REPLICA_EXPECTED_HOUR` supõe, o alerta está certo sobre o relógio e errado sobre o fato. Ajuste a variável.

**Logs:**
```bash
ls -lt /var/log/easyhealth/bi_replica_*.log | head -3
tail -50 /var/log/easyhealth/bi_replica_$(date +%Y%m%d)*.log
```

**Ação inicial:**
1. `AVISO: heartbeat ... não registrado` no log → o script rodou mas não alcançou a aplicação. Confira `EASYHEALTH_COMPOSE_FILE` no env file (`/etc/easyhealth/bi_replica.env`).
2. `replica com N views bi_observability_*, esperado 5` → rode na produção:
   ```bash
   docker compose -f docker-compose.prod.yml exec -T api bundle exec rake observability:bi_views:apply
   ```
3. Falha de dump/restore → o banco BI atual **não** foi substituído (por desenho); dá para investigar sem pressa.

**Resolver quando:** houver um refresh bem-sucedido registrado no heartbeat.

---

## 8. Nenhum evento Android chegou

**Confirmar:** sub-check `android_analytics_ingestion_stale`.

> Se estiver **cinza** (`insufficient_data`), o volume médio está abaixo do piso de tráfego e a ausência não é conclusiva. Não investigue ainda.

**SQL:**
```sql
SELECT date_trunc('hour', occurred_at) AS hora, COUNT(*)
FROM product_analytics_events
WHERE platform = 'android' AND occurred_at > NOW() - INTERVAL '24 hours'
GROUP BY 1 ORDER BY 1 DESC;

-- houve tráfego que deveria ter gerado eventos?
SELECT COUNT(*) FROM app_installations
WHERE platform = 'android' AND last_seen_at > NOW() - INTERVAL '2 hours';
```

**Ação inicial:**
1. Instalações ativas mas zero eventos → a ingestão parou. Verifique `ANALYTICS_INGESTION_ENABLED` e `MOBILE_ANALYTICS_ENABLED` no servidor, e `NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED` no build do front (essa é `NEXT_PUBLIC_*` e exige **rebuild**, não restart).
2. Zero instalações ativas também → não há tráfego; não é falha de pipeline.
3. Teste o endpoint diretamente: `POST /api/v1/analytics/events`.

---

## 9. API ficou lenta

**Confirmar:** card **API & Infraestrutura**, `api_latency_p95`.

**Limitação importante:** essa medição é do processo Puma vivo, últimos 15 min, e zera a cada deploy. Ela não vê CPU, memória, disco nem o PostgreSQL.

```bash
docker compose -f docker-compose.prod.yml logs api --since 30m \
  | grep -o '{"ts".*' | jq -c 'select(.duration_ms > 2000) | {route, duration_ms, status}' \
  | sort | uniq -c | sort -rn | head -20
```

**Ação inicial:**
1. Uma rota específica → investigar essa query (`EXPLAIN`).
2. Tudo lento → checar o banco:
   ```sql
   SELECT count(*), state FROM pg_stat_activity GROUP BY state;
   SELECT pid, now() - query_start AS duracao, left(query, 120)
   FROM pg_stat_activity WHERE state = 'active' ORDER BY duracao DESC LIMIT 10;
   ```
3. Recursos da VPS: `docker stats`, `df -h`, `free -m`.

---

## 10. Container reiniciou

**Não há detecção automática nesta entrega.** Sinais indiretos:

- Vários heartbeats voltando a `insufficient_data` ao mesmo tempo.
- `make_delivery_backlog` crescendo (a fila `:async` foi perdida).
- `HttpStats` zerado — o card **API & Infraestrutura** fica cinza com poucas requisições.

```bash
docker compose -f docker-compose.prod.yml ps
docker inspect --format '{{.Name}} restarts={{.RestartCount}} started={{.State.StartedAt}}' $(docker compose -f docker-compose.prod.yml ps -q)
docker compose -f docker-compose.prod.yml logs api --tail 200
```

**Ação inicial:**
1. Confirmar se foi deploy (esperado) ou OOM/crash.
2. Se OOM: `dmesg | grep -i oom`.
3. Reprocessar o que a fila perdeu: `rake make_webhook:retry_pending`.
