# Sentry Audit — Easy Health
_Data: 2026-05-26_

---

## Backend (Rails)

| Item | Status | Detalhe |
|------|--------|---------|
| `sentry-ruby` + `sentry-rails` instalados | ✅ OK | v6.5.0 em `Gemfile` |
| `config/initializers/sentry.rb` existe | ✅ OK | Presente e configurado |
| DSN via variável de ambiente | ✅ OK | `ENV["SENTRY_DSN"]` — nunca hardcoded |
| `enabled_environments` restrito | ✅ OK | `%w[staging production]` — dev não polui o projeto |
| `environment` correto | ✅ OK | `Rails.env` |
| `release` com commit SHA | ✅ OK | `ENV["GIT_COMMIT"]` injetado pelo CI no `.env` a cada deploy |
| `traces_sample_rate` configurado | ✅ OK | `0.1` em production, `0.0` em outros |
| `send_default_pii` desabilitado | ✅ OK | `false` — nenhum dado pessoal automático |
| `filter_parameters` cobre secrets | ✅ OK | Cobre `password`, `token`, `secret`, `key`, `dsn`, `authorization` |
| `before_send` filtra request body | ✅ OK | Substitui strings brutas por `[FILTERED]` |
| Contexto de usuário seguro | ✅ OK | `id` + email mascarado (`a***@domínio`) em `BaseController` |
| Rota de teste Sentry | ✅ OK | `GET /api/v1/debug/sentry_test` — bloqueada em production |
| `GIT_COMMIT` no deploy CI | ✅ OK | `deploy.yml` injeta SHA no `.env` de forma idempotente |

---

## Frontend (Next.js)

| Item | Status | Detalhe |
|------|--------|---------|
| `@sentry/nextjs` instalado | ✅ OK | `^8` adicionado ao `package.json` |
| `sentry.client.config.ts` | ✅ OK | DSN via `NEXT_PUBLIC_SENTRY_DSN`, `tracesSampleRate` 0.1/0.0 |
| `sentry.server.config.ts` | ✅ OK | DSN server-side, `release` via `GIT_COMMIT` |
| `instrumentation.ts` | ✅ OK | Carrega config server no Node.js e Edge; captura via `onRequestError` |
| `withSentryConfig` no `next.config.ts` | ✅ OK | Source maps ocultos, logger silenciado |
| CSP `connect-src` inclui `*.sentry.io` | ✅ OK | Adicionado — sem isso eventos são bloqueados pelo browser |
| `error.tsx` (error boundary) | ✅ OK | Captura exceções React via `Sentry.captureException` |
| `global-error.tsx` (root boundary) | ✅ OK | Cobre erros no root layout |
| Captura de `ApiError` >= 500 | ✅ OK | `src/shared/lib/api.ts` envia erros 5xx ao Sentry |
| `NEXT_PUBLIC_SENTRY_DSN` no Dockerfile | ✅ OK | Build ARG + ENV no `web/Dockerfile` |
| `NEXT_PUBLIC_SENTRY_DSN` no Compose | ✅ OK | Build arg + environment em `docker-compose.prod.yml` |
| `send_default_pii` desabilitado | ✅ OK | `false` em ambas as configs |

---

## O que ainda FALTA / Próximos ajustes

| Item | Prioridade | Ação recomendada |
|------|-----------|-----------------|
| Definir `SENTRY_DSN` e `NEXT_PUBLIC_SENTRY_DSN` no `.env` de produção | 🔴 Alta | Criar projeto no sentry.io e colar o DSN no `.env` do VPS |
| Testar rota `GET /api/v1/debug/sentry_test` em staging | 🟡 Média | Verificar se o evento chega no dashboard Sentry |
| Alertas configurados no Sentry | 🟡 Média | Criar regras de alerta para erros novos e spike de erros |
| Source maps no CI (opcional) | 🟢 Baixa | Adicionar `SENTRY_AUTH_TOKEN` e `SENTRY_ORG/PROJECT` para upload automático |
| Sentry para Sidekiq / Active Job | 🟢 Baixa | Adicionar `sentry-sidekiq` se houver workers |

---

## Riscos

| Risco | Mitigação |
|-------|-----------|
| DSN público no frontend (`NEXT_PUBLIC_SENTRY_DSN`) | Aceitável — DSN de ingest é publicamente seguro; rate limiting configurado no Sentry |
| `tracesSampleRate: 0.1` pode gerar custo em volume alto | Reduzir para `0.05` se o plano tiver limite de transactions |
| `captureException` em 5xx pode duplicar eventos com `onRequestError` | Monitorar no dashboard; ajustar se houver duplicação excessiva |
| `global-error.tsx` sem Tailwind (carrega antes do CSS global) | Botão usa classes inline como fallback; aceitável para erro crítico |

---

## Como testar

```bash
# Backend — dispara erro de teste em staging/dev
curl http://localhost:3001/api/v1/debug/sentry_test

# Frontend — após npm install e next build, erros 5xx e boundaries estão ativos
# Para simular: chamar um endpoint que retorna 500 e verificar no dashboard Sentry
```
