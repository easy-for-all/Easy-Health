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

## Eventos-gatilho de push (já emitidos hoje)

| Evento | Onde é emitido | Semântica |
| --- | --- | --- |
| `activation_workout_created` | `workout_plans_controller` (tempo real, ao criar plano) | usuário criou o 1º plano — Make aplica delay e manda lembrete |
| `plan_created_but_not_used` | `relationship_daily_job` / `relationship_backfill_job` (diário, idempotente) | plano existe mas nunca foi usado |
| `never_created_workout`, `user_inactive_3_days`, `user_inactive_7_days` | jobs de relationship | recuperação/reengajamento |

`workout_created_not_started` **não** é um evento emitido — é apenas um nome de
**segmento** (`user_segments`), calculado por `UserSegmentCalculator`.

## Payload (versionado, sem PII sensível, NUNCA com token FCM)

`MakeWebhookClient#payload_for`. Campos relevantes para push:

```json
{
  "schema_version": 1,
  "event_id": 123,
  "event_name": "activation_workout_created",
  "occurred_at": "2026-07-16T10:00:00Z",
  "source": "activation_push",
  "environment": "production",
  "user": { "id": 123, "timezone": "America/Sao_Paulo", "locale": "pt-BR" },
  "metadata": { "plan_id": 456, "trigger_type": "activation_workout_created" }
}
```

- `timezone` (de `users.time_zone`, fallback `America/Sao_Paulo`) é o que o Make
  usa para agendar no horário local do usuário.
- O "context" do enunciado é carregado em `metadata` (mantido para não quebrar os
  cenários de e-mail já configurados no Make).
- `email`/`name` só aparecem com `MAKE_WEBHOOK_PAYLOAD_MODE=full`.

## Assinatura (inalterada — mantém o e-mail funcionando)

```
X-EasyHealth-Signature = HMAC-SHA256(MAKE_WEBHOOK_SECRET, "<event_id>.<timestamp>.<raw_body>")
```
Headers: `X-EasyHealth-Event-Id`, `-Event-Name`, `-Timestamp`, `-Signature`.
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
