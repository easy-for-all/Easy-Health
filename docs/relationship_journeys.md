# Relationship Journeys

## Visão geral

A EasyHealth registra fatos de produto em `user_events`, calcula segmentos em `user_segments` e envia somente eventos permitidos para o Make.app. O backend não escreve campanhas, templates ou jornadas: ele apenas registra fatos estruturados e entrega payloads seguros.

Eventos internos nunca dependem de `marketing_consent`, `unsubscribed_at` ou `email_bounced_at`. Esses campos bloqueiam apenas comunicação externa, marketing e jornadas de relacionamento.

## Eventos e segmentos

Eventos iniciais suportados incluem cadastro/trial, assinatura, criação de plano, treino concluído/parcial/abandonado, foto corporal, inatividade, trial expirado e plano criado sem uso. Eventos técnicos antigos, como `ai_workout_generated`, continuam compatíveis via `UserEventService`.

Segmentos iniciais:

- `trial_active`, `trial_expiring_soon`, `trial_expired`
- `subscriber_active`, `subscriber_canceled`
- `never_created_workout`, `workout_created_not_started`, `first_workout_done`
- `active_user`, `inactive_3_days`, `inactive_7_days`, `inactive_15_days`
- `high_intent_trial`, `churn_risk`, `returning_user`
- `uploaded_body_photo`, `no_body_photo`, `completed_partial_recently`

## Make.app

Configure:

```bash
MAKE_WEBHOOK_URL=
MAKE_WEBHOOK_SECRET=
MAKE_WEBHOOK_ENABLED=false
MAKE_WEBHOOK_TIMEOUT_SECONDS=10
MAKE_WEBHOOK_PAYLOAD_MODE=minimal
MAKE_WEBHOOK_ALLOWED_EVENTS=
MAKE_EVENT_SCHEMA_VERSION=1
MAKE_EVENT_CHANNEL_ROUTING_ENABLED=false
```

`MAKE_WEBHOOK_ALLOWED_EVENTS` é uma whitelist separada por vírgula. Lista vazia não envia nenhum evento por segurança.

Exemplo:

```bash
MAKE_WEBHOOK_ALLOWED_EVENTS=trial_day_3,trial_day_6,trial_expired_without_subscription,user_inactive_7_days,first_workout_completed,workout_completed_partial,churn_risk
```

Além da whitelist, a entrega exige `MAKE_WEBHOOK_ENABLED=true`, URL/secret configurados e usuário elegível para relacionamento: não anonimizado, não deletado, `marketing_consent=true`, sem `unsubscribed_at`, sem `email_bounced_at` e e-mail válido.

## Payload e assinatura

Headers enviados:

- `X-EasyHealth-Event-Id`
- `X-EasyHealth-Event-Name`
- `X-EasyHealth-Timestamp`
- `X-EasyHealth-Signature`

Assinatura:

```ruby
OpenSSL::HMAC.hexdigest("SHA256", MAKE_WEBHOOK_SECRET, "#{event_id}.#{timestamp}.#{body_json}")
```

`MAKE_WEBHOOK_PAYLOAD_MODE=minimal` envia `user.id`, evento, segmentos, assinatura/engajamento e metadata sanitizada. `full` inclui e-mail/nome, mas ainda só quando o usuário é elegível para relacionamento.

`MAKE_EVENT_SCHEMA_VERSION=2` adiciona `delivery.channels` e `context`. O Make
deve usar `delivery.channels` para separar email/push e `event_name` apenas para
o evento de negocio. Veja `docs/make-event-contract.md`.

## Jobs

Rodar jornada diária:

```bash
rails runner "RelationshipDailyJob.perform_now"
```

Dry-run do backfill:

```bash
rails runner "RelationshipBackfillJob.perform_now(dry_run: true)"
```

Aplicar backfill sem disparar Make para retroativos:

```bash
rails runner "RelationshipBackfillJob.perform_now(dry_run: false)"
```

Permitir Make para retroativos somente de forma explícita:

```bash
rails runner "RelationshipBackfillJob.perform_now(dry_run: false, allow_make_delivery: true)"
```

Reprocessar um evento:

```bash
rails runner "MakeWebhookDeliveryJob.perform_later(EVENT_ID)"
```

## Backfill

O backfill recalcula segmentos e cria eventos de estado atual para usuários existentes. No `dry_run`, nada é gravado nem enviado. O relatório mostra usuários processados, mudanças de segmento, eventos que seriam criados, eventos elegíveis para Make e eventos suprimidos.

No `apply`, eventos retroativos recebem `source: relationship_backfill` e `metadata.retroactive=true`. A entrega ao Make fica desabilitada por padrão, mesmo que o evento esteja na whitelist.

## Troubleshooting

- Evento gravado mas não enviado: confira `make_delivery_status`, whitelist, `MAKE_WEBHOOK_ENABLED`, URL/secret e elegibilidade do usuário.
- Lista vazia em `MAKE_WEBHOOK_ALLOWED_EVENTS`: comportamento esperado é não enviar nada.
- Make fora do ar: o evento fica registrado como `failed`, com erro em `make_last_error`, e o job tenta novamente até 5 vezes.
- Payload com PII inesperada: use `MAKE_WEBHOOK_PAYLOAD_MODE=minimal` e revise metadata enviada ao tracker.
