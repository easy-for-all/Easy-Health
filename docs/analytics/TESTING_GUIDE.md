# Testing Guide — Analytics

## Backend (RSpec)

```
cd api && bundle exec rspec spec/services/analytics spec/requests/api/v1/analytics spec/models/user_reportable_spec.rb
```

Cobertura desta entrega:
- `metric_result_spec` — % nunca negativo, clamp >100 = `inconsistent`, `no_coverage`,
  `insufficient_sample`.
- `event_catalog_spec` — taxonomia carrega, server-tracked, enums.
- `ingestion_spec` — persiste server-sink; rejeita desconhecido (+ `analytics_event_rejected`);
  strip de chaves sensíveis; idempotência (idempotency_key não duplica); `activation_platform`
  setado uma vez e nunca sobrescrito; GA4-only não persiste; flag desliga ingestão.
- `events_spec` (request) — aceita anônimo; associa `user_id` no servidor ignorando o do
  cliente; lote grande → 413; sem eventos → 400.
- `reporting_time_spec` — zone default BR; SQL com `AT TIME ZONE`; cohort maturity.
- `user_reportable_spec` — exclui test/anonimizado/deletado + domínios internos.

## Frontend (Vitest)

```
cd web && npx vitest run
```

- `analytics-taxonomy.test.ts` — **paridade** TS ⇔ `api/config/analytics/events.yml`
  (nomes, sinks, versão). Falha se divergirem.
- `analytics-context.test.ts` — `anonymous_id` estável; `session_id` por sessão;
  `startAnalyticsSession` renova; first_open uma vez; plataforma web/desktop no jsdom.

## Casos obrigatórios (checklist)

- [x] % nunca negativo; clamp a [0,100].
- [x] Mesmo `idempotency_key` não cria evento duplicado.
- [x] Usuário sem 7 dias fora do denominador D7 (base `created_at <= 7.days.ago`).
- [x] `activation_platform` fixa a coorte (não reclassifica por sessão).
- [x] Payload sensível é removido / rejeitado.
- [x] `user_id` vem do servidor, nunca do cliente.
- [x] Push aberto 2× = 1 conversão (`Analytics::PushAttributionService`, `push_attribution_service_spec`).
- [x] Treino iniciado antes do push não recebe atribuição (idem).
- [x] `environment=test` não dispara para sinks reais (`sinksEnabled()`).

## Verificação manual (DebugView / Network)

`npm run dev`, abrir landing → GA4 DebugView mostra eventos; Network mostra
`POST /api/v1/analytics/events` com `platform`/`app_surface`/`anonymous_id`/`session_id`.
Android: abrir/fechar/reabrir → `app_first_open` uma vez, `app_opened`/`app_resumed`/
`app_backgrounded` sem duplicar, `app_version`+`build_number` presentes.
