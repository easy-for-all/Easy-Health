# Android Analytics — EasyHealth

## Arquitetura: WebView do site remoto

O app Android (`com.EasyHealth.myapp`, Capacitor 8) é um **wrapper que carrega
`https://easyhealth.art`** (`web/capacitor.config.ts`, `server.url`). Consequência:
**o ponto único de instrumentação é o frontend web** — não há SDK de analytics nativo,
nem Firebase Analytics (só FCM/Messaging para push). **Decisão:** não adicionar SDK
nativo (evita segundo projeto Firebase e dupla contagem com o gtag da WebView).

## O que é instrumentado nativamente (via `@capacitor/app`)

`web/src/shared/lib/analytics/lifecycle.ts` (init em `analytics/init.ts`):

- `app_first_open` — **idempotente por instalação** (`localStorage: eh_installed`).
- `app_opened` — no boot nativo.
- `app_resumed` / `app_backgrounded` — via `appStateChange` (guarda anti-duplicação).
- `app_updated` — compara `App.getInfo().version` com a salva.
- `deep_link_opened` — via `appUrlOpen` (só o path, nunca a URL completa).
- `app_version` (+ `build_number`) — de `App.getInfo()`; anexado a todo evento pelo contexto.

Regras garantidas: first_open uma vez por instalação; resume não duplica; logout **não**
apaga `anonymous_id`; login associa a instalação ao usuário; nada bloqueia o boot;
fila offline com cap (100) + TTL (6h) + flush no background (`sendBeacon`).

## Distinções importantes (não confundir)

- **Play Store acquisition / download** — só via relatórios da Play Console (externo).
- **first_open** — medido no dispositivo (`app_first_open`).
- **installation record** — `app_installations` (ver "Métricas de instalação" abaixo).
- Nunca chamar `first_open` de "download" no painel.

## Métricas de instalação no painel admin (Marco 2)

**`AppInstallation` é a única fonte de verdade interna para contagem de instalações.**
Serviço: `Analytics::AndroidInstallations` · endpoint `GET /api/v1/admin/analytics/android_installations`
· UI `web/src/app/(app)/admin/android-installations-section.tsx`.

Nunca usar como equivalente de instalação: `users.activation_platform`, `DeviceToken`,
`ProductAnalyticsEvent`, eventos `app_opened` ou sessões. Todos aparecem no painel, mas
em blocos próprios e rotulados como o que são.

### Definições

| Termo | Definição |
|---|---|
| Instalação Android | `AppInstallation.for_platform("android")`. Web/PWA nunca entram. |
| Instalação vinculada | `user_id` preenchido (scope `linked`). Métrica principal de reconciliação. |
| Instalação anônima | `user_id` nulo. **Não é erro** — pode ter instalado e ainda não autenticado. |
| Instalação autenticada | `user_id` **e** `last_authenticated_at` preenchidos (scope `fully_authenticated`). |
| Ativa em 7 / 30 dias | `last_seen_at >= 7.days.ago` / `30.days.ago`. |
| Taxa de vínculo | vinculadas ÷ total × 100. Denominador zero devolve `0.0` com `status: "no_coverage"`, nunca NaN. |
| Usuários Android únicos | `COUNT(DISTINCT user_id)` entre as vinculadas. **Instalação ≠ usuário**: um usuário pode ter várias. |

### Instalação ≠ usuário ≠ download

- **Instalação**: um registro em `app_installations`, criado quando o app fala com a API pela primeira vez.
- **Usuário**: uma conta. Um usuário com dois aparelhos gera duas instalações.
- **Download da Play Store**: número oficial da Play Console, sempre **maior** (inclui quem
  instalou e nunca abriu). O backend não recebe esse número; o bloco "Google Play" do painel
  existe com `configured: false` e permanece vazio até a integração ser feita.

### Build 45 — início da reconciliação confiável

`AppInstallation::RECONCILIATION_MIN_BUILD = 45` (app v1.0.45) é a **fonte única** do limiar,
usada por scopes (`current_build` / `legacy_build`), serviço, rake task e UI (que lê o valor
do payload, sem hardcode). A partir desse build o app envia `X-Installation-Id` em toda
requisição autenticada e o backend reconcilia `AppInstallation.user_id` (Marco 1).

Por isso o painel separa três visões que **nunca se misturam**:

1. **Histórico** — todas as instalações Android já registradas.
2. **Tracking atual (build 45+)** — a única medida honesta da saúde do fluxo atual.
3. **Legado (build < 45, ausente ou não numérico)** — registros anteriores à correção;
   suas instalações anônimas são esperadas e diluiriam permanentemente a taxa atual.

`app_build` é string livre (`nil`, `""`, `"unknown"`, `"45"`, `"0045"` coexistem). A
classificação usa `AppInstallation::NUMERIC_BUILD_SQL`, que só converte para inteiro o que
casa com `^[0-9]{1,9}$` — uma linha malformada nunca quebra uma agregação.

### Blocos exibidos

Visão geral · Saúde do tracking (build 45+, com amostra sempre visível) · Legado ·
Qualidade dos dados · Adoção de versão · Vínculo por dia (14 dias) · Saúde operacional ·
Versões do app · Dispositivos (fabricante, modelo, versão do Android) · Pipeline de analytics ·
Google Play (não integrado) · Funil de usuários vinculados.

Limiares de saúde da taxa de vínculo: **≥ 95% saudável · ≥ 85% atenção · < 85% crítico ·
amostra 0 = sem dados**. A saúde operacional deriva apenas de sinais reais
(`Register.enabled?`, `FirebasePushService.configured?`, `DeviceToken`, eventos das últimas
24h, `UserEvent.make_delivery_status`); sem sinal o componente reporta `unknown`, nunca "ok".

Limites de agrupamento: versões 20 · fabricantes 10 · modelos 15 · versões do Android 15.
Valores vazios ficam `NULL` no banco e só recebem o rótulo "não informado" na apresentação.

### Privacidade

A resposta é agregada: nenhum `installation_id`, e-mail ou `user_id` individual. Coberto por
teste (`spec/requests/api/v1/admin/android_installations_spec.rb`).

### Validação read-only

```bash
docker compose exec api bundle exec rails mobile_tracking:installation_metrics
```

Não escreve nada e não imprime dado pessoal.

### Limitações conhecidas

- Não há número oficial de downloads da Play Store neste banco.
- Instalações anteriores ao build 45 podem permanecer anônimas para sempre.
- Um mesmo aparelho reinstalado gera um novo `installation_id` (nova instalação).
- Sem cache: as métricas são calculadas a cada request (≈18 queries agregadas).

### Fica para o Marco 3

Backfill/consolidação de instalações legadas duplicadas, integração com a Play Console
Developer API, índices compostos em `app_installations` (se a tabela crescer muito) e
validação de `AppInstallation::SOURCES` na escrita.

## Configuração manual necessária (Firebase / Play)

- **Firebase**: `google-services.json` é injetado só no CI (não versionado); confirmar
  que o projeto Firebase é o **mesmo** de produção antes de qualquer mudança. **Não criar
  segundo projeto.** Firebase Analytics **não** será habilitado nesta arquitetura.
- **Play Console**: usar relatórios de aquisição/instalação para o funil de download →
  first_open (não reconstruir download no backend).
- **Build**: `versionCode`/`versionName` vêm de `ANDROID_VERSION_CODE`/`ANDROID_VERSION_NAME`
  (env do build). `build_number` agora é capturado em runtime via `App.getInfo().build`.

## Limitações

- `@capacitor/device` não instalado → `os_version` é `navigator.userAgent`.
- Sem deep links Android reais (intent-filters `VIEW`/App Links) — "deep link" hoje é
  roteamento pós-push.
