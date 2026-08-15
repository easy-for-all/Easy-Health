# Webhook de evento → Make (orquestração de push)

Como os eventos de negócio da EasyHealth chegam ao Make para que ele decida
**se/quando/qual template** de push enviar. Reaproveita 100% a infra de
relacionamento já existente (`user_events` → `MakeWebhookClient` →
`MakeWebhookDeliveryJob`), sem webhook novo.

## Fluxo

```
Evento de negócio (ex.: activation_workout_created)
 → UserEventService.track  → user_events (outbox, make_delivery_status=pending)
 → MakeWebhookDeliveryJob  → MakeWebhookClient (POST assinado)  → Make
 → Make aplica regra/horário/template
 → Make → POST /api/v1/integrations/make/push_dispatches  (ver make-push-orchestration)
```

## Eventos-gatilho

> **Fonte de verdade:** `api/config/communication_events.yml`. A tabela oficial,
> com canais e `notification_type`, está em
> [event-orchestration.md](event-orchestration.md#2-catálogo-dos-orchestration-events)
> e [push-journey-v1.md](push-journey-v1.md). Esta seção é orientação, não
> catálogo — se divergir, o YAML vence.

| Evento | Onde é emitido | Semântica |
| --- | --- | --- |
| `activation_workout_created` | `workout_plans_controller` (tempo real, ao criar plano) | usuário criou o 1º plano — *signal*, ver aviso abaixo |
| `first_workout_not_started_2h` / `_24h` | `FirstWorkoutNotStarted{2h,24h}Job` | não iniciou o 1º treino |
| `scheduled_workout_reminder_due` | `ScheduledWorkoutReminderSchedulerJob` | lembrete no horário preferido |
| `first_workout_completed` | `WorkoutSessionsController` | 1º treino concluído |
| `user_inactive_3_days`, `user_inactive_7_days` | `RelationshipDailyJob` | recuperação/reengajamento |

> `activation_workout_created` chegar ao Make **não** significa push imediato.
> Ele é `activation_reminder` (categoria de engagement): um push imediato consome
> o cooldown de 20h e faria `first_workout_not_started_2h` ser pulado com
> `cooldown_active`. O cenário deve receber e rotear o evento sem push imediato
> até essa interferência ser decidida.

`plan_created_but_not_used` e `never_created_workout` são **e-mail**, não push.

`workout_created_not_started` **não** é um evento emitido — é apenas um nome de
**segmento** (`user_segments`), calculado por `UserSegmentCalculator`.

## Payload (versionado, sem PII sensível, NUNCA com token FCM)

O contrato completo esta em `docs/make-event-contract.md`. No schema v2, o Make
deve rotear primeiro por `delivery.channels` e depois por `event_name`.

Campos relevantes para push:

```json
{
  "schema_version": 2,
  "event_id": 123,
  "event_name": "activation_workout_created",
  "occurred_at": "2026-07-16T10:00:00Z",
  "source": "easyhealth_backend",
  "environment": "production",
  "delivery": { "channels": ["push"] },
  "user": { "id": 123, "timezone": "America/Sao_Paulo", "locale": "pt-BR" },
  "context": {},
  "metadata": { "trigger_source": "activation_push" }
}
```

- `timezone` (de `users.time_zone`, fallback `America/Sao_Paulo`) é o que o Make
  usa para agendar no horário local do usuário.
- O schema 1 continua disponivel temporariamente com `MAKE_EVENT_SCHEMA_VERSION=1`.
- `email`/`name` só aparecem com `MAKE_WEBHOOK_PAYLOAD_MODE=full`.

## Assinatura (inalterada — mantém o e-mail funcionando)

```
X-EasyHealth-Signature = HMAC-SHA256(MAKE_WEBHOOK_SECRET, "<event_id>.<timestamp>.<raw_body>")
```
Headers: `X-EasyHealth-Event-Id`, `-Event-Name`, `-Schema-Version`,
`-Timestamp`, `-Signature`.
Retry/backoff em `MakeWebhookDeliveryJob` (`MAX_ATTEMPTS=5`); status na própria
linha do `user_events` (`make_delivery_status`).

## Configuração manual (VPS / .env) — passo operacional

Adicionar os eventos de push ao gate (CSV; vazio = nada é enviado):

```env
MAKE_WEBHOOK_ENABLED=true
MAKE_WEBHOOK_URL=<url do Custom Webhook do Make>
MAKE_WEBHOOK_SECRET=<segredo compartilhado>
MAKE_WEBHOOK_ALLOWED_EVENTS=activation_workout_created,plan_created_but_not_used
```

## ⚠️ Ressalva de consentimento (decisão pendente)

`MakeWebhookEligibility.user_eligible_for_relationship?` exige `marketing_consent?`.
Isso é correto para e-mail (marketing), mas **push funcional de treino não é
marketing** — é regido por `user_notification_preferences` (push_enabled +
workout_reminders_enabled), revalidado no endpoint de dispatch.

Consequência: hoje, um usuário que **recusou marketing** mas **aceitou push** não
tem o evento entregue ao Make → não recebe o push, mesmo tendo optado por ele.
Nenhum push indevido é enviado (o endpoint revalida), mas há **sub-entrega**.

Corrigir isso exige separar a elegibilidade por canal (evento "push-elegível"
gated por push prefs, não por marketing_consent) — mudança que afeta o gate
compartilhado com o e-mail e **não foi feita neste pass** para evitar regressão de
consentimento no fluxo de e-mail. Decidir na fase de migração gradual.
