# Make Event Contract

## Objetivo

`event_name` descreve o que aconteceu no produto. `delivery.channels` descreve
por quais canais esse evento pode gerar comunicacao.

O backend envia um unico webhook por `UserEvent`. O Make deve primeiro separar
por `delivery.channels` e, dentro de cada canal, separar por `event_name`.

## Schema version 2

Exemplo para `workout_created_not_started`:

```json
{
  "schema_version": 2,
  "event_id": 1120,
  "event_name": "workout_created_not_started",
  "occurred_at": "2026-07-18T15:06:35Z",
  "source": "easyhealth_backend",
  "environment": "development",
  "delivery": {
    "channels": ["email", "push"]
  },
  "user": {
    "id": 9,
    "timezone": "America/Sao_Paulo",
    "locale": "pt-BR"
  },
  "segments": [],
  "subscription": {
    "status": "none",
    "trial_ends_at": "2026-06-28T12:17:08Z",
    "plan": "none"
  },
  "engagement": {
    "created_at": "2026-05-17T15:37:04Z",
    "last_sign_in_at": null,
    "last_workout_at": null,
    "total_workouts_created": 1,
    "total_workouts_completed": 0,
    "days_since_last_workout": null
  },
  "context": {
    "workout_id": 123,
    "plan_id": 123,
    "workout_created_at": "2026-07-18T14:00:00Z",
    "minutes_since_creation": 66
  },
  "metadata": {
    "trigger_source": "manual_test",
    "note": "make webhook smoke test"
  }
}
```

Campos:

- `schema_version`: `1` durante compatibilidade ou `2` para o contrato novo.
- `event_id`: id do `user_events`, usado para correlacao e idempotencia.
- `event_name`: evento de negocio, sem prefixo de canal.
- `source`: origem raiz fixa do produtor do contrato, `easyhealth_backend`.
- `delivery.channels`: canais suportados pelo evento. Valores atuais: `email`, `push`.
- `context`: dados de negocio diretamente ligados ao evento.
- `metadata`: diagnostico operacional; use `trigger_source`, nao `source`.

`delivery.channels` pode ser `[]`. Isso significa evento observavel sem
comunicacao configurada.

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
event_name = "workout_created_not_started"
```

Nao crie `email_workout_created_not_started` nem
`push_workout_created_not_started`. Nao duplique o Custom Webhook apenas para
mudar canal.

## Migracao

Variaveis:

```env
MAKE_EVENT_SCHEMA_VERSION=1
MAKE_EVENT_CHANNEL_ROUTING_ENABLED=false
```

Etapas:

1. Em development, ativar `MAKE_EVENT_SCHEMA_VERSION=2` e
   `MAKE_EVENT_CHANNEL_ROUTING_ENABLED=true`.
2. Validar no Make que `delivery.channels` chega como array.
3. Adicionar router principal por canal e manter router por `event_name` dentro
   de cada canal.
4. Testar eventos somente email, somente push, multicanal e sem canal.
5. Ativar schema 2 em producao sem remover schema 1 imediatamente.

Rollback:

```env
MAKE_EVENT_SCHEMA_VERSION=1
MAKE_EVENT_CHANNEL_ROUTING_ENABLED=false
```

Eventos ja em retry mantem o payload salvo em `user_events.payload_json`, para a
assinatura e a idempotencia continuarem estaveis.

## Tasks de teste

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
