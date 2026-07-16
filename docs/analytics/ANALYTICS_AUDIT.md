# Analytics Audit — EasyHealth

_Auditoria realizada em 2026-07-15 como base da revisão de Product Analytics._

## Ferramentas atuais

| Ferramenta | Onde | Papel |
|---|---|---|
| GA4 (`G-FG3BDM75T1`) | `web/src/app/layout.tsx` (gtag inline) | Eventos comportamentais |
| Google Ads (`AW-17759537883`) | mesmo gtag | Conversões |
| Microsoft Clarity (`wwdmi83dip`) | `web/src/app/layout.tsx` | Gravação/diagnóstico Web |
| Sentry | backend (`sentry-ruby`/`sentry-rails`), rota `debug/sentry_test` | Erros backend. **Ausente no frontend** (só CSP liberado) |
| FCM (Firebase Messaging) | `@capacitor/push-notifications` + `FirebasePushService` | Push Android. **Sem Firebase Analytics** |
| Make (webhook) | `RelationshipEventTracker` → `MakeWebhookDeliveryJob` | Eventos de relacionamento/marketing |

## Arquivos responsáveis (antes desta entrega)

- Frontend GA4/Ads: `web/src/shared/lib/analytics.ts` (agora `analytics/index.ts`)
- Funil server-side legado: `web/src/shared/lib/onboarding-tracking.ts` → `POST /api/v1/onboarding_events`
- Detecção de plataforma: `web/src/shared/lib/platform.ts` (só Native vs Web)
- Push: `web/src/shared/lib/pushNotifications.ts`, `api/app/services/push_dispatch_service.rb`, `activation_push_attribution.rb`
- Admin: `api/app/controllers/api/v1/admin_controller.rb` (monolítico), `onboarding_analytics_service.rb`

## Sistemas de eventos existentes

1. **`user_events`** (`RelationshipEventTracker`, ~80 eventos) → Make. Sanitiza via `SENSITIVE_KEY_PATTERN`.
2. **`onboarding_events`** (`OnboardingEventTracker`) → `OnboardingAnalyticsService`. Não vai para o Make.
3. **`activation_events`** — tabela **órfã** (sem model, sem uso). Tinha `platform`/`session_id`/`origin`. **Removida** nesta entrega; papel assumido por `product_analytics_events`.

Eventos GA4-only (sem consumidor no backend): a maioria dos `EVENTS` do `analytics.ts` (screen_view, cta_click, app_promo_*). Eventos de push eram **strings soltas** fora do catálogo.

## Inconsistências encontradas (e status)

| Inconsistência | Evidência | Status |
|---|---|---|
| Retenção D1/D7/D30 usa `DATE()` sem timezone (app UTC / base BR) | `admin_controller.rb` retenção | **Corrigido** via `Analytics::ReportingTime` (AT TIME ZONE) |
| "Executou treino" com duas definições (`joins(:workout_sessions)` vs `completion_status:"completed"`) | `admin_controller.rb:30` vs `OnboardingAnalyticsService` | **Corrigido** — definição única = completed |
| Contas admin/teste e anonimizados poluem métricas | nenhuma query filtrava | **Corrigido** via `User.reportable` |
| Percentuais podem passar de 100% / negativos | conversões sem clamp | **Corrigido** — clamp [0,100] + `MetricResult` |
| Sem dimensão de plataforma real | `platform:"android"` hard-coded | **Corrigido** — `product_analytics_events.platform` + `users.activation_platform` |
| GA4 nunca recebia `user_id` | `layout.tsx` | **Corrigido** — `identifyUser()` |
| Sem `anonymous_id`/`session_id` | — | **Corrigido** — `analytics/context.ts` |
| Sem Consent Mode (LGPD) | gtag/Clarity incondicionais | **Corrigido** — Consent Mode v2 default denied |
| Sem lifecycle nativo (first_open/resume) | `@capacitor/app` só `getInfo()` | **Corrigido** — `analytics/lifecycle.ts` |
| Sentry ausente no frontend | — | **Corrigido** — `@sentry/nextjs` via `instrumentation-client.ts`/`instrumentation.ts`, tags platform/app_surface/app_version, breadcrumb em falha de analytics |

## Riscos monitorados

- **Dupla contagem**: `screen_view` manual pode duplicar page_view do enhanced measurement do GA4 (mitigar no GA4, ver `GA4_CONFIGURATION.md`).
- **Timezone**: métricas fora do módulo `ReportingTime` ainda usam UTC — migrar por domínio.
- **Eventos duplicados por remount/Strict Mode**: mitigado com `trackOnce`.
- **Eventos perdidos ao fechar o app**: mitigado com fila + `flushOnBackground` (sendBeacon) e TTL de 6h.
- **Usuários deletados**: excluídos via `reportable` e no Make; sessões já são destruídas na anonimização.

## Cobertura confiável

Eventos `product_analytics_events` (funil por plataforma, ativação, retenção de valor auditável) têm cobertura **a partir da data de deploy desta entrega**. Métricas reconstruídas de tabelas existentes (planos, sessões) são `historical_derived`. Ver `METRIC_DEFINITIONS.md`.
