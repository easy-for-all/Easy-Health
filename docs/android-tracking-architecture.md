# Android Tracking — Arquitetura

Ver o diagnóstico e a causa raiz do n=1 em `docs/android-tracking-audit.md`.

## Visão geral

O app Android é um shell Capacitor que carrega `https://easyhealth.art` no WebView.
O tracking tem **três destinos**, por tipo de informação:

```
                    ┌─────────────────────── app (WebView) ───────────────────────┐
  lifecycle ───────▶│ analytics/lifecycle.ts  session.ts  screen.ts               │
  navegação  ──────▶│ analytics/index.ts (dispatch + routing)                     │
  instalação ──────▶│ analytics/installation.ts ──▶ POST /app/installations       │
  consentimento ───▶│ analytics/consent.ts / firebase.ts                          │
                    └───────┬───────────────┬───────────────────┬─────────────────┘
                            │               │                   │
                   (web/PWA)│      (android nativo)             │ (eventos server-sink, sempre)
                            ▼               ▼                   ▼
                        GA4 (gtag)   Firebase Analytics    Backend próprio
                                     Crashlytics/Perf      product_analytics_events
                                                           app_installations
```

Regra de roteamento (anti-duplicidade, `index.ts`):
- **web/PWA** → GA4 (gtag). **android nativo + Firebase ativo** → Firebase nativo **apenas**
  (GA4 suprimido). **Eventos server-sink** → backend próprio, sempre (fonte de verdade).

## Módulos frontend (`web/src/shared/lib/analytics/`)
| Arquivo | Papel |
|---|---|
| `index.ts` | dispatch central + roteamento de destino + identify/reset |
| `context.ts` | detecção robusta de plataforma, anonymous_id, session_id, installation_id mirror |
| `installation.ts` | installation_id persistente (`@capacitor/preferences`), register/refresh |
| `session.ts` | janela de sessão de 30 min (funções puras) |
| `screen.ts` | rota→screen_name estável + `useScreenTracking` (dedup) |
| `lifecycle.ts` | `@capacitor/app` cold start / resume / background / app_updated / deep link |
| `firebase.ts` | ponte nativa Analytics/Crashlytics/Performance (no-op fora do nativo) |
| `consent.ts` | Consent Mode v2 + espelho para Firebase |
| `server.ts` | fila batched + retry/beacon para o backend |
| `taxonomy.ts` | espelho de `api/config/analytics/events.yml` (paridade por teste) |

## Backend (`api/`)
| Componente | Papel |
|---|---|
| `AppInstallation` + migration | registro estável de instalação (installation_id único) |
| `AppInstallations::Register` | upsert idempotente, associação pós-login, flag `MOBILE_ANALYTICS_ENABLED` |
| `Api::V1::App::InstallationsController` | `POST /register`, `PATCH /:installation_id` (auth opcional) |
| `Analytics::Ingestion` + `EventCatalog` | ingestão de `product_analytics_events` (já existente) |
| `Analytics::AndroidInstallations` | painel "App Android" (base real por app_installations) |
| `Analytics::PushAttributionService` | atribuição push→treino (janela 2h/24h, já existente) |
| `MobileTracking::BackfillInstallations` | backfill de device_tokens → app_installations + activation_platform |

## Identidade
- `installation_id`: UUID por instalação, sobrevive a logout, recriado só em reinstalação.
- `anonymous_id`: visitante/thread anônimo (localStorage).
- `session_id`: sessão (regenerado por timeout de 30 min no nativo / tab na web).
- `user_id`: setado no login; associa a instalação (`last_authenticated_at`). Firebase usa
  o id interno pseudônimo (nunca email/installation_id).

## Fluxo de instalação
1. Boot nativo → `registerInstallation()` (anônimo) → `app_installations` (source `register`).
2. Login → `identifyUser()` re-registra com cookie de sessão → associa `user_id`.
3. Painel "App Android" conta a base real; backfill recupera o histórico de `device_tokens`.
