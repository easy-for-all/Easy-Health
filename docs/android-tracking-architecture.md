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

## Feature flags e constantes

| Flag / constante | Onde | Default | Papel |
|---|---|---|---|
| `MOBILE_ANALYTICS_ENABLED` | backend `AppInstallations::Register` | off | liga registro de instalação |
| `NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED` | `installation.ts` | off | liga register/refresh no app |
| `NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED` | `firebase.ts` | off | Analytics nativo + roteamento anti-dup |
| `NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED` | `firebase.ts` | off | Crashlytics nativo |
| `NEXT_PUBLIC_FIREBASE_PERFORMANCE_ENABLED` | `firebase.ts` | off | Performance nativo |
| `INSTALL_REFERRER_ENABLED` | backend `Register` | off | captura do Play Install Referrer |
| `ANALYTICS_INGESTION_ENABLED` | `Analytics::Ingestion` | on | ingestão de eventos (já existente) |
| `SESSION_TIMEOUT_MINUTES` | `session.ts` | 30 | janela de sessão |
| `TRACKING_VERSION` | `installation.ts` | 2 | versão do tracking enviada no register |
| `START_WINDOW` / `COMPLETE_WINDOW` | `Analytics::PushAttributionService` | 2h / 24h | janela de atribuição push→treino |

Todas as flags têm default **seguro (off)**; ligar exige set explícito. Padrão backend:
`ActiveModel::Type::Boolean.new.cast(ENV.fetch("FLAG","false"))`.

## Resiliência (offline/retry) e observabilidade — status
- **Fila offline + retry**: `server.ts` já implementa fila batched (cap 100), TTL 6h,
  flush no background via `sendBeacon`, sem PII, nunca bloqueia o app. Não foi criada
  mensageria nova (reuso, conforme Fase 20).
- **Eventos de erro de negócio**: já na taxonomia (`workout_load_failed`,
  `workout_save_failed`, `push_registration_failed`, `deep_link_failed`,
  `analytics_event_rejected`). Ingestão registra rejeições sem payload sensível.
- **Logs estruturados**: `AppInstallations::Register` loga `installation_registered` /
  `installation_refreshed` (JSON, sem PII); ingestão loga falhas por classe.
- **Sampling** (`TELEMETRY_SAMPLE_RATE`): recomendado para telemetria de alto volume —
  configurar quando `screen_view`/lifecycle nativos entrarem em produção.

