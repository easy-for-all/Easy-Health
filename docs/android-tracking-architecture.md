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
  Fonte de verdade **exclusiva** no nativo: `@capacitor/preferences`
  (SharedPreferences `CapacitorStorage`), que está **fora do Android Auto Backup**
  (`android-config/res/xml/{backup_rules,data_extraction_rules}.xml`). O localStorage é
  espelho **write-only** no nativo — o diretório da WebView É restaurado pelo backup, então
  um id que só existe lá pertence à instalação anterior. Ver "Identidade de instalação e
  Android Auto Backup" abaixo.
- `anonymous_id`: visitante/thread anônimo (localStorage).
- `session_id`: sessão (regenerado por timeout de 30 min no nativo / tab na web).
- `user_id`: setado no login; associa a instalação (`last_authenticated_at`). Firebase usa
  o id interno pseudônimo (nunca email/installation_id).

## Fluxo de instalação
1. Boot nativo → `registerInstallation()` (anônimo) → `app_installations` (source `register`).
2. Login → `identifyUser()` re-registra com cookie de sessão → associa `user_id`.
3. Painel "App Android" conta a base real; backfill recupera o histórico de `device_tokens`.

## Eventos de autenticação: dois conjuntos, finalidades diferentes

Autenticação emite **dois** conjuntos de eventos, que não se substituem.

| | Taxonomia interna | Recomendados do Firebase |
|---|---|---|
| Nomes | `signup_completed`, `login_completed`, `social_login_completed` | `sign_up`, `login` |
| Sinks | server (`events.yml`) + GA4 na web / Firebase no nativo, via `trackEvent` | **só** Firebase nativo, via `logFirebaseEvent` |
| Parâmetros | `auth_attempt_id`, `provider`, `intent`, `auth_screen` | apenas `method` (`email` \| `google`) |
| Para quê | funil de produto, Admin, investigação por tentativa | otimização de campanha no Google Ads |
| Onde | `features/auth/auth-analytics.ts` | idem, funções `trackSignupCompleted` / `trackLoginCompleted` / `trackSocialLoginCompleted` |

Pontos que não podem ser perdidos num refactor:

1. Os eventos internos **continuam existindo como sempre**. Os recomendados são aditivos.
2. `sign_up`/`login` **não** passam pelo `trackEvent` e **não** estão em `events.yml` /
   `taxonomy.ts`: pelo dispatch central eles também iriam para o GA4 na web, criando uma
   segunda contagem paralela de cadastro/login. `logFirebaseEvent` já é no-op fora do nativo
   (`firebaseAnalyticsActive() = isNativeApp() && NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED`),
   então o isolamento Android/Web é estrutural.
3. Uma operação, um evento: criar conta já autentica, então cadastro emite `sign_up` e **não**
   também `login`. `login` é o acesso posterior de quem já existe.
4. Novo vs existente no Google vem **do backend** (`new_user` em
   `Api::V1::Auth::GoogleNativeController`), que o marca em `User#newly_registered` no ponto
   exato em que `User.from_omniauth` insere a linha. Nada é inferido no cliente, e nada é
   persistido em `localStorage`: um aparelho pode legitimamente criar mais de uma conta.
   A dedupe do cliente é só em memória, por `authAttemptId`, contra duplo disparo do React.
5. As telas Google fazem `window.location.replace` logo em seguida, o que derruba o contexto
   JS da WebView. Por isso o envio é aguardado com orçamento de 800 ms — que resolve, nunca
   rejeita: analytics não pode atrasar nem quebrar o redirect.

## Identidade de instalação e Android Auto Backup

**Problema (jul/2026):** o app subia com `android:allowBackup="true"` e sem regras. O Auto
Backup restaurava o data dir inteiro — inclusive `shared_prefs/CapacitorStorage.xml` — então
uma reinstalação voltava reivindicando o `installation_id` da instalação anterior. Um usuário
novo (501) logou num aparelho onde o id pertencia ao usuário 13: o backend recusou transferir
a posse (`link_result=conflict`, correto) e a conta nova ficou com zero `AppInstallation`.

**Regras hoje:**

| Evento | `installation_id` |
|---|---|
| Update do app (mesmo data dir) | **mantido** |
| Logout / login | **mantido** |
| Desinstalar + reinstalar, ou limpar dados | **novo** |
| Restore de backup / transferência entre aparelhos | **novo** |

O que sustenta isso:

1. **Backup rules** excluem só `CapacitorStorage` (cloud-backup **e** device-transfer). Nada
   mais é excluído: sessão e dados do usuário na WebView continuam restaurando.
2. Com o store fora do backup, "existe `eh_installation_id` no Preferences" passa a
   significar "criado por ESTA instalação". `installation.ts` nunca adota o espelho do
   localStorage no nativo.
3. Store sem resposta (plugin ausente/bridge travada) **não** é store vazio: nesse caso o id
   não é regerado, senão cada boot lento criaria uma instalação nova.
4. Ao detectar instalação nova, `anonymous_id`, `eh_installed` e os marcadores de versão
   também são descartados — senão o aparelho restaurado segue reportando como o anterior.

**Recuperação de conflito (`link_status=conflict`)** — só com evidência, nunca automática:
o cliente grava `eh_installation_linked` no Preferences quando o backend confirma o vínculo.
Conflito **com** esse marcador = troca de conta legítima no mesmo aparelho → não mexe em
nada (a posse continua com o dono original). Conflito **sem** o marcador = id restaurado →
gera um id novo **uma única vez** (`eh_installation_regenerated`), registra a nova
instalação e emite `installation_id_regenerated`. O backend não afrouxa nada: quem cria a
`AppInstallation` nova é o cliente, com um id novo.

**Validar em aparelho** (build debug):

```bash
# id atual no store durável
adb shell run-as com.EasyHealth.myapp cat shared_prefs/CapacitorStorage.xml

# update mantém o id
adb install -r app-debug.apk        # → mesmo eh_installation_id

# reinstalação gera id novo
adb uninstall com.EasyHealth.myapp && adb install app-debug.apk

# simular restore de backup (é o cenário que quebrou em produção)
adb shell bmgr enable true
adb shell bmgr backupnow com.EasyHealth.myapp
adb uninstall com.EasyHealth.myapp
adb install app-debug.apk           # → id novo, mesmo com o backup restaurado
```

**Usuários já criados sem vínculo:** nada de cirurgia no banco. Listar os afetados e deixar
o próprio app se recuperar no próximo boot (o fix de cliente é web, chega sem AAB novo):

```ruby
# User não tem has_many :app_installations (só AppInstallations::LinkToUser escreve user_id).
User.where(signup_source: "android")
    .where.not(id: AppInstallation.linked.select(:user_id))
    .pluck(:id, :email)
```

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

