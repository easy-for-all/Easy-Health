# Android Tracking Audit — EasyHealth (Fase 0)

_Auditoria de 2026-07-20 que fundamenta a evolução completa do tracking Android._
_Complementa (não substitui) `docs/analytics/ANALYTICS_AUDIT.md` (2026-07-15) e
`docs/analytics/ANDROID_ANALYTICS.md`. Onde este documento diverge daqueles, ele
**prevalece** e a divergência está marcada como **[REVISÃO DE DECISÃO]**._

---

## 1. Problema

O painel "Impacto do app Android" mostra **Android n=1**, **Web n=23**, **PWA n=0**,
apesar de ~150 instalações Android reais na Play Store.

## 2. Causa raiz (comprovada)

O card `n=` vem de `data.cohorts[k].cohort_size`
(`web/src/app/(app)/admin/platform-comparison-section.tsx:106`), calculado em
`api/app/services/analytics/platform_comparison.rb:33-39`:

```ruby
def base(platform)
  User.reportable.where(activation_platform: platform)   # <- fonte única
end
```

Ou seja: **Android n=1 == `User.reportable.where(activation_platform:"android").count == 1`**.

A coluna `users.activation_platform`:

- Criada em `api/db/migrate/20260715120001_add_analytics_columns_to_users.rb` (**2026-07-15**,
  há 5 dias), `:string` nullable, **sem backfill** → os ~150 Android históricos são `NULL`
  e **não entram em nenhuma coorte**.
- É **write-once**, gravada só em `api/app/services/analytics/ingestion.rb:108-118`
  (`return unless @user && activation_platform.blank?`).
- Exige uma cadeia frágil e simultânea:
  1. evento com sink `server` chega a `POST /api/v1/analytics/events`;
  2. `current_user` presente (**sessão Devise por cookie** — o cliente nunca envia `user_id`,
     `events_controller.rb:25`);
  3. `Capacitor.isNativePlatform() == true` **e** `platform == "android"`
     (`web/src/shared/lib/analytics/context.ts:63-70`);
  4. o evento ocorre **após 2026-07-15**.

### 2.1 Por que Web=23 mas Android=1 (assimetria)

- **Web**: `initAnalytics()` dispara `web_session_started` em **todo** boot
  (`analytics/init.ts`), que é server-sink (`events.yml:29`) → carimba `activation_platform="web"`
  com facilidade e imediatamente.
- **Android**: depende de `app_opened`/`app_first_open` (também server-sink) **mais** o cookie
  de sessão cruzando subdomínios (`easyhealth.art` ↔ `api.easyhealth.art`) dentro do WebView,
  em `fetch(..., credentials:"include")` (`analytics/server.ts:119-125`). Qualquer falha de
  cookie → `current_user == nil` → `set_activation_platform!` retorna cedo → Android nunca carimbado.
- **Agravante — misclassificação**: se `Capacitor.isNativePlatform()` retornar `false` no
  WebView remoto (bundle servido de `https://easyhealth.art`), `detectPlatform()` cai em
  `return "web"` → usuários Android reais são carimbados como **web** (infla Web, zera Android),
  consistente com 23 vs 1.

### 2.2 A base real já existe (e o painel ignora)

`device_tokens` (`api/db/schema.rb:255-275`) tem `platform default:"android"` e contém os ~150
dispositivos reais. **O painel não usa essa tabela.** É a fonte confiável para backfill (Fase J).

### 2.3 Verificação read-only sugerida (contra o DB de produção)

```sql
SELECT activation_platform, COUNT(*) FROM users GROUP BY 1;         -- esperado: maioria NULL
SELECT platform, COUNT(*) FROM device_tokens GROUP BY 1;            -- esperado: ~150 android
SELECT platform, COUNT(*) FROM product_analytics_events GROUP BY 1; -- android vs web vs unknown → mede misclassificação
```

## 3. Arquitetura atual

**O app Android não empacota assets** — carrega `https://easyhealth.art` no WebView
(`web/capacitor.config.ts`, `server.url`). O bundle Next.js de produção **é** o app.
Logo GA4, Clarity, Sentry-JS e todo o serviço de analytics rodam dentro do WebView, iguais à web.
A única nativização é observar o lifecycle via `@capacitor/app`.

- Backend: Rails 8.1 em `api/`. Web/Capacitor em `web/`. `web/android/` é **efêmero** (o CI
  recria via `npx cap add android` e sobrescreve a partir de `web/android-config/`).
- Serviço central de analytics: `web/src/shared/lib/analytics/*` (index, context, lifecycle,
  server, taxonomy, consent, init). **Maduro, porém ainda não em `main`** — vive na cadeia
  de branches `ajuste-fluxo-web-*`.

## 4. Integrações existentes (resumo — detalhe em `docs/analytics/ANALYTICS_AUDIT.md`)

| Ferramenta | Onde | Papel | Nativo? |
|---|---|---|---|
| GA4 `G-FG3BDM75T1` + Ads `AW-17759537883` | `web/src/app/layout.tsx:12-66` (gtag inline) | Comportamental / conversões | Não (WebView) |
| Clarity `wwdmi83dip` | `web/src/app/layout.tsx:67-73` | Diagnóstico web | Não (WebView) |
| Sentry `@sentry/nextjs` | `web/src/instrumentation-client.ts`, `instrumentation.ts` | Erros JS/Rails | Não |
| FCM | `@capacitor/push-notifications` + `FirebasePushService` | Push | **Messaging apenas** |
| Make | `RelationshipEventTracker` → `MakeWebhookDeliveryJob` | Relacionamento/marketing | Backend |

- **Firebase Analytics / Crashlytics / Performance: AUSENTES** (só messaging transitivo).
- `@capacitor/device` e `@capacitor/preferences`: **não instalados** → IDs em `localStorage`;
  `os_version` é `navigator.userAgent`.

## 5. Modelos e endpoints backend relevantes

- `device_tokens` (`schema.rb:255`) — registro por token FCM; upsert em
  `POST /api/v1/device_tokens`. Não é installation estável.
- `product_analytics_events` (`schema.rb:602`) — telemetria de produto;
  `POST /api/v1/analytics/events` (auth opcional) → `Analytics::Ingestion`.
- `user_events` (`schema.rb:776`) — relacionamento → Make (`RelationshipEventTracker::EVENTS`).
- `push_dispatches` (`schema.rb:646`) — auditoria push Make; **já tem `correlation_id`**.
- `notification_deliveries` (`schema.rb:514`) — activation push interno; `converted_at`, `opened_at`.
- `onboarding_events` (`schema.rb:542`) — funil de onboarding legado.
- `users.activation_platform` (`schema.rb:868`) — coorte do painel (write-once).
- **Não existe** `app_installations` nem endpoint de installation.

## 6. Taxonomia e eventos

Fonte única: `api/config/analytics/events.yml` (espelhada em `web/.../analytics/taxonomy.ts`
por teste de paridade). Sinks `server`/`ga4`/`clarity`; `PLATFORMS = android/web/pwa/unknown`.

**Já existem** (reutilizar, não recriar): `app_install_attributed`, `app_first_open`,
`app_opened`, `app_backgrounded`, `app_resumed`, `app_updated`, `deep_link_opened`,
`push_token_registered`, `push_permission_*`, `push_opened`, `push_deep_link_resolved`,
`workout_started_after_push`, `workout_completed_after_push`, funil de treino/onboarding/subscription.

**Ausentes (a adicionar sem renomear)**: `installation_registered`/`installation_refreshed`,
`session_started`/`session_ended`, `screen_view`, `push_received_foreground`,
`push_action_clicked`, `offline_mode_entered`/`offline_sync_completed`/`sync_failed`,
`push_retry`/`push_token_invalidated`, erros de negócio adicionais.

## 7. Riscos

- **Duplicidade GA4×Firebase**: com Firebase Analytics nativo, o mesmo evento pode sair pelo
  gtag da WebView **e** pelo SDK nativo → dupla contagem. Mitigar por roteamento de destino (Fase F).
- **Privacidade**: `server.ts` e Clarity **não** checam consent hoje; installation_id não pode
  virar Firebase user id; PII proibida por allowlist (Fase L).
- **Regressão**: adicionar deps Firebase mexe no Gradle/CI do AAB publicado — risco ao app na
  Play. Mitigar: verificar compat Cap 8 antes, flags OFF por default, build debug local.
- **Backfill**: não inventar `installed_at` histórico; usar `first_seen_at`/`tracking_started_at`.

## 8. [REVISÃO DE DECISÃO] SDK Firebase nativo

`docs/analytics/ANDROID_ANALYTICS.md` documentou **não** adicionar SDK nativo. **Esta auditoria
reverte** essa decisão a pedido do produto:

- **Motivo Analytics**: dar cobertura Android confiável independente da fragilidade do cookie no
  WebView; DebugView/Android para validação.
- **Motivo Crashlytics**: Sentry-JS no WebView **não** captura crashes/ANRs nativos — lacuna real.
- **Motivo Performance**: métricas de app start nativo que a camada web não enxerga.
- **Guardrails**: mesmo projeto Firebase existente (`google-services.json` do CI); sem segundo
  projeto; eventos críticos permanecem no **backend próprio** como fonte de verdade; roteamento
  anti-duplicidade (Fase F); PII nunca ao Firebase.

## 9. Dependências necessárias (a confirmar compat Capacitor 8 antes de instalar)

- Frontend: `@capacitor/preferences`, `@capacitor/device`,
  `@capacitor-firebase/analytics`, `@capacitor-firebase/crashlytics`,
  `@capacitor-firebase/performance` (e provável `@capacitor-firebase/app`).
- Gradle: Firebase BOM + módulos + plugins crashlytics/perf em `web/android-config/`.
- Nenhuma gem nova prevista no backend (usar padrões existentes).

## 10. Plano incremental

Ver `/home/marcus/.claude/plans/*` (plano aprovado). Ordem: Fase A (este doc) → B (plataforma +
installation_id) → C (`app_installations` backend + associação) → D (sessões/telas/funil) →
E (Firebase nativo) → F (anti-duplicidade) → G (push attribution) → H (install referrer) →
I (painel) → J (backfill) → K (erros/offline/flags) → L (privacidade/docs/checklists).
Cada fase com testes verdes e migrations reversíveis; flags default OFF; sem quebrar
push/Make/GA4/login/CI.
