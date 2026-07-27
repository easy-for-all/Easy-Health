# Observabilidade — EasyHealth

Responder em minutos, não em dias: **o sistema está saudável e os usuários estão conseguindo completar a jornada?**

Esta é a **Entrega 1**: contexto de requisição, logs estruturados, eventos de autenticação e vínculo, heartbeats, checks, incidentes, alertas internos, painel admin, views BI e testes.

> **Fora do escopo desta entrega:** Prometheus, Grafana Alloy, dashboards e alertas Grafana, OpenTelemetry e o webhook `/integrations/grafana/alerts`. Nenhuma gem nova foi adicionada. Ver [ARCHITECTURE.md](ARCHITECTURE.md#o-que-ainda-nao-existe).

## Componentes

| Componente | Onde | Para quê |
|---|---|---|
| `Observability::Context` | `api/app/models/observability/context.rb` | Correlação: request_id, plataforma, build, refs hasheados |
| `ObservabilityRequestContext` | `api/lib/middleware/` | Popula o contexto e emite `http_request_completed` |
| `Observability::Logger` | `api/app/services/observability/` | Logs JSON em stream próprio |
| `Observability::Events` | idem | Fachada única: log + `product_analytics_events` |
| `Observability::Heartbeat` | idem | Liveness dos processos recorrentes |
| `Observability::HealthCheckRunner` | idem | Executa os checks, persiste, reconcilia incidentes |
| `Observability::IncidentManager` | idem | Abre, deduplica, escala, resolve |
| `Observability::Notifier` | idem | Webhook genérico (desligado por padrão) |
| `Observability::Dashboard` | idem | Payload dos seis cards |
| Views `bi_observability_*` | `api/db/views/` | Consumo pela réplica BI / Power BI |

Tabelas: `observability_heartbeats`, `observability_check_results`, `observability_incidents`.
**Nenhuma tabela de eventos nova** — `product_analytics_events` já atendia.

## Como rodar localmente

```bash
docker compose exec api bin/rails db:migrate
docker compose exec api bundle exec rake observability:heartbeats   # registra os processos
docker compose exec api bundle exec rake observability:check        # roda os checks
docker compose exec api bundle exec rake observability:status       # último status de cada check
```

Painel: `/admin/observability` (requer conta admin).

Logs JSON localmente:

```bash
OBSERVABILITY_JSON_LOGS=true docker compose up api
```

Em produção o stream JSON é sempre ligado. Em teste e desenvolvimento fica desligado por padrão para não poluir a saída.

## Como ver incidentes

```bash
docker compose exec api bundle exec rake observability:open_incidents
```

Ou no painel, tabela **Incidentes**, com filtros de status, severidade e origem. Reconhecer/resolver pelo painel grava quem fez (`admin:<id>`).

## Como testar alertas

Alertas vêm **desligados** (`OBSERVABILITY_ALERTS_ENABLED=false`). Para testar:

```bash
OBSERVABILITY_ALERTS_ENABLED=true \
OBSERVABILITY_ALERT_WEBHOOK_URL=https://hook.exemplo/teste \
docker compose exec api bundle exec rake observability:test_alert
```

Em produção a task exige `CONFIRM_PRODUCTION_ALERT_TEST=true`. O incidente de teste é construído em memória e **não** é persistido.

## Cron necessário

Não instalamos nada automaticamente. Ver [RUNBOOK.md](RUNBOOK.md#cron-necessario).

```
*/15 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.prod.yml exec -T api bundle exec rake observability:check
```

## Documentos

- [ARCHITECTURE.md](ARCHITECTURE.md) — fluxos, decisões e limitações conhecidas
- [ALERT_MATRIX.md](ALERT_MATRIX.md) — cada check, janela, amostra mínima, thresholds e ação
- [RUNBOOK.md](RUNBOOK.md) — dez cenários de investigação
- [BI_VIEWS.md](BI_VIEWS.md) — views SQL e consultas de exemplo
- [PRIVACY.md](PRIVACY.md) — o que nunca entra em observabilidade
