# Make Event Contract

## Objetivo

`event_name` descreve o que aconteceu no produto. `delivery.channels` descreve
por quais canais esse evento pode gerar comunicacao.

O backend envia um unico webhook por `UserEvent`. O Make deve primeiro separar
por `delivery.channels` e, dentro de cada canal, separar por `event_name`.

## Schema version 2

Schema 2 e o contrato canonico (default). O bloco `delivery` e sempre explicito
e o payload traz um bloco tecnico por canal: `email` (quando o evento envia
email) e `push` (quando envia push).

### Exemplo — email (`trial_day_3`)

```json
{
  "schema_version": 2,
  "event_id": 5332,
  "event_name": "trial_day_3",
  "occurred_at": "2026-07-20T08:00:11Z",
  "source": "easyhealth_backend",
  "environment": "production",
  "delivery": {
    "channels": ["email"],
    "communication_type": "lifecycle",
    "engagement": false
  },
  "email": {
    "template_key": "trial_day_3"
  },
  "user": {
    "id": 479,
    "timezone": "America/Fortaleza",
    "locale": "pt-BR"
  },
  "metadata": {
    "days_since_trial_start": 3
  }
}
```

### Exemplo — push (`first_workout_not_started_2h`)

```json
{
  "schema_version": 2,
  "event_id": 5400,
  "event_name": "first_workout_not_started_2h",
  "delivery": {
    "channels": ["push"],
    "communication_type": "activation",
    "engagement": true
  },
  "push": {
    "notification_type": "activation_reminder",
    "route": "/workouts/ready",
    "campaign_key": "first_workout_not_started_2h"
  },
  "user": { "id": 13, "locale": "pt-BR", "timezone": "America/Sao_Paulo" }
}
```

### Exemplo — multicanal (`user_inactive_7_days`)

```json
{
  "delivery": {
    "channels": ["push", "email"],
    "communication_type": "retention",
    "engagement": true
  },
  "email": { "template_key": "user_inactive_7_days" },
  "push": {
    "notification_type": "workout_reminder",
    "route": "/workouts/ready",
    "campaign_key": "user_inactive_7_days"
  }
}
```

Campos:

- `schema_version`: `1` durante compatibilidade ou `2` para o contrato novo.
- `event_id`: id do `user_events`, usado para correlacao e idempotencia.
- `event_name`: evento de negocio, sem prefixo de canal.
- `source`: origem raiz fixa do produtor do contrato, `easyhealth_backend`.
- `delivery.channels`: canais do evento. Valores atuais: `email`, `push`.
- `delivery.communication_type`: bucket editorial (`lifecycle`, `activation`,
  `progress`, `retention`).
- `delivery.engagement`: `true` se o evento conta para o cap de frequencia.
- `email.template_key`: chave do template no Make (default = `event_name`). A
  copia/HTML fica no Make, nunca no payload.
- `push.notification_type` / `push.route` / `push.campaign_key`: descritor
  tecnico do push. `campaign_key` = `event_name`. Titulo/corpo ficam no Make.
- `context`: dados de negocio diretamente ligados ao evento.
- `metadata`: diagnostico operacional; use `trigger_source`, nao `source`.

Eventos sem comunicacao configurada NAO chegam ao Make: o backend marca a
entrega como `skipped` (`unknown_communication_event` /
`communication_event_disabled`) e nao inventa canal padrao.

## Canais

A fonte unica de canais por evento e `api/config/communication_events.yml`,
exposta por:

```ruby
CommunicationEvents.channels_for("workout_created_not_started")
CommunicationEvents.supports_channel?("workout_created_not_started", "push")
```

Eventos conhecidos omitidos da configuracao retornam `[]`. Eventos desconhecidos
falham de forma controlada. Canais arbitrarios nao sao aceitos.

`delivery.channels` nao e autorizacao final de envio. A EasyHealth continua sendo
a fonte de verdade para consentimento, opt-out, tokens ativos e limites. O Make
orquestra templates, delays, campanhas e chamadas para o endpoint de push.

## Routing no Make

Fluxo recomendado:

```text
Custom Webhook
-> filtro de environment
-> router principal por delivery.channels
   -> email
      -> filtro: delivery.channels contem "email"
      -> router por event_name
      -> template/regra de email
      -> Brevo
   -> push
      -> filtro: delivery.channels contem "push"
      -> router por event_name
      -> template/regra de push
      -> POST /api/v1/integrations/make/push_dispatches
```

Dentro de cada canal, use tambem o evento:

```text
delivery.channels contem "push"
AND
event_name = "first_workout_not_started_2h"
```

IMPORTANTE: as rotas de email e push NAO sao exclusivas. Em um evento multicanal
(`["push","email"]`) as DUAS rotas devem executar. Use um roteador com filtros
independentes por canal (ou dois filtros paralelos), nunca um router exclusivo
onde so a primeira condicao verdadeira roda.

Nao crie `email_<event>` nem `push_<event>`. Nao duplique o Custom Webhook
apenas para mudar canal.

## Divisao de responsabilidade

Antes do Make (Rails decide): evento conhecido/habilitado, canais previstos,
consentimento basico e elegibilidade tecnica, e se o webhook e disparado.

No Make (Make decide): template, titulo, corpo, idioma, variante, provedor,
sequencia, atraso, roteamento de canal e a chamada final ao endpoint de push ou
ao provedor de email.

Elegibilidade final de push e decidida quando o Make chama
`POST /api/v1/integrations/make/push_dispatches` (o endpoint retorna
`status`/`sent`/`skip_reason`). O Make NAO deve tratar HTTP 200 como envio
confirmado — precisa inspecionar `sent` e `skip_reason`.

## Migracao e schema 1

Variavel:

```env
MAKE_EVENT_SCHEMA_VERSION=2
```

Schema 2 e o default do codigo. `MAKE_EVENT_SCHEMA_VERSION` existe apenas como
override de rollback. Nao ha mais `MAKE_EVENT_CHANNEL_ROUTING_ENABLED`.

Cauda de schema 1: eventos persistidos antes desta entrega podem, em retries,
reemitir o payload salvo em `user_events.payload_json` (schema 1). Cada emissao
schema 1 loga `make_schema_v1_emitted` (event_id, event_name). Criterio de
remocao do caminho schema 1: quando `make_schema_v1_emitted` zerar por 7 dias
consecutivos, remover `schema_one_payload` e a rota de compatibilidade no Make.

Rollback imediato (sem redeploy):

```env
MAKE_EVENT_SCHEMA_VERSION=1
```

## Tasks de teste

Auditoria read-only da configuracao canonica (exit != 0 se invalida):

```bash
bundle exec rake communication_events:audit
```

Preview do payload canonico por `event_name` (sem persistir nem enviar):

```bash
bundle exec rake "communication_events:preview[trial_day_3,mail.marcus.reis@gmail.com]"
```

Envio manual controlado pelo pipeline canonico (respeita consentimento,
`source=manual_communication_test`, idempotency key unica de smoke test):

```bash
bundle exec rake "communication_events:deliver[trial_day_3,mail.marcus.reis@gmail.com]"
```

As tasks `make:*` abaixo continuam disponiveis e aceitam override manual de
canal (`CHANNELS=`) para cenarios de smoke test especificos.

Preview sem persistir nem enviar:

```bash
bin/rails "make:preview_event[mail.marcus.reis@gmail.com,workout_created_not_started]"
```

Teste com envio:

```bash
CHANNELS=email,push bin/rails "make:test_event[mail.marcus.reis@gmail.com,workout_created_not_started]"
```

Dry-run da task de teste:

```bash
DRY_RUN=true CHANNELS=email,push bin/rails "make:test_event[mail.marcus.reis@gmail.com,workout_created_not_started]"
```

Em producao, envio manual exige:

```env
CONFIRM_PRODUCTION_MAKE_TEST=true
```

## Seguranca

- O payload outbound para Make nao inclui token FCM.
- Secrets de Firebase, Make, email, Stripe ou chaves de API sao removidos da
  metadata por sanitizacao.
- `MAKE_WEBHOOK_PAYLOAD_MODE=minimal` nao envia email nem nome.
- A assinatura continua sendo HMAC-SHA256 do corpo bruto final:

```text
<event_id>.<timestamp>.<raw_body>
```

- Headers enviados incluem `X-EasyHealth-Event-Id`,
  `X-EasyHealth-Event-Name`, `X-EasyHealth-Schema-Version`,
  `X-EasyHealth-Timestamp` e `X-EasyHealth-Signature`.

## Nota sobre workout_created_not_started

`workout_created_not_started` existe no catalogo de relacionamento, mas a
documentacao atual de push indica que ele nao possui produtor automatico nesta
base. Esta entrega suporta o contrato, preview e teste manual para esse nome,
sem criar uma nova emissao automatica.
