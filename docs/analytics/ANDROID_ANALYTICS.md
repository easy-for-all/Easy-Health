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
- **installation record** — `app_installations` (fase futura; hoje `anonymous_id`).
- Nunca chamar `first_open` de "download" no painel.

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
