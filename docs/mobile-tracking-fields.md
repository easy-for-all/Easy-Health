# Mobile tracking — semântica dos campos

Referência curta para não confundir três conceitos que parecem "plataforma" mas
respondem a perguntas diferentes. Complementa `docs/android-tracking-audit.md` e
`docs/android-tracking-architecture.md`.

## Plataforma: três campos, três perguntas

### `AppInstallation.platform`
**Pergunta:** em que runtime esta instalação está rodando *agora*?
**Fonte de verdade para métricas de instalação.** Vem da detecção do cliente
(`Capacitor.getPlatform()` → `web/src/shared/lib/analytics/context.ts`), gravada em
todo register/refresh. Valores: `android | web | pwa | unknown`. `native=true` só é
coerente com `android` (web/pwa/unknown são normalizados para `native=false` no model).
É o que o painel Android (`Analytics::AndroidInstallations`) conta.

### `User.activation_platform`
**Pergunta:** em que plataforma este usuário *se ativou*?
**Write-once, nunca sobrescrito depois de válido.** É preenchido por:
1. o primeiro evento não-`unknown` do usuário (`Analytics::Ingestion#set_activation_platform!`); e
2. **(novo)** a associação autenticada de uma `AppInstallation` nativa Android — apenas
   quando ainda estiver em branco (`AppInstallations::Register#backfill_activation_platform!`).

Não é a fonte de verdade da instalação; é um atributo do usuário para coortes.

### `User.consent_source`
**Pergunta:** *onde* o consentimento (LGPD/termos) foi coletado?
Vem do fluxo de cadastro (`registrations_controller.rb`, OmniAuth, Google native).
**Não representa a plataforma do app.** É a origem do consentimento — normalmente o
formulário web, que é renderizado *dentro* do WebView nativo.

### Combinação válida
```
activation_platform = "android"   # runtime nativo detectado
consent_source      = "web"       # consentimento coletado no formulário web (no WebView)
```
Isso **não** é inconsistência de dado: o app Android carrega o site remoto
(`capacitor.config.ts` → `server.url = https://easyhealth.art`), então o mesmo
formulário web roda dentro do app nativo.

## Timestamps da instalação

| Campo | Quando é atualizado |
|-------|---------------------|
| `last_seen_at` | **Qualquer** contato válido da instalação com o backend (register e refresh/update). |
| `last_session_at` | **Somente** início real de sessão nativa (boot do app), sinalizado explicitamente pelo cliente via `session_started: true`. Nunca inflado por refresh nem por re-register pós-login. |
| `last_authenticated_at` | **Somente** quando há `current_user` e a instalação é associada a ele. |
| `first_seen_at` / `tracking_started_at` | Apenas na criação do registro. |
| `installed_at` | Nunca inventado quando desconhecido (fica `NULL`; backfill não o forja). |

## Feature flags (kill-switch, default LIGADO)

O registro de instalação é **ligado por padrão**; a flag só serve para desligar.
(Os arquivos `.env.example` de `api/` e `web/` são gitignored neste repo, por isso a
documentação canônica das flags fica aqui.)

| Flag | Camada | Default | Desliga com | Como aplicar mudança |
|------|--------|---------|-------------|----------------------|
| `MOBILE_ANALYTICS_ENABLED` | Backend (`AppInstallations::Register.enabled?`) | ligado | `=false` | restart/redeploy da API |
| `NEXT_PUBLIC_MOBILE_ANALYTICS_ENABLED` | Frontend (`installation.ts`) | ligado | `=false` | **rebuild** do frontend (é `NEXT_PUBLIC_*`, inlined no build) |

A causa raiz do `AppInstallation.count = 0` em produção foi justamente essas duas flags
terem ficado **desligadas por default** enquanto ninguém setava a env — resolvido tornando
o default ligado no código.

### Por que `session_started` é explícito
O endpoint `POST /api/v1/app/installations/register` é chamado em **dois** momentos:
- boot nativo (`init.ts`) → é início de sessão → envia `session_started: true`;
- pós-login (`identifyUser` em `index.ts`) → **não** é nova sessão → **não** envia o flag.

Por isso `last_session_at` depende de um sinal explícito do chamador, e não do verbo HTTP.
