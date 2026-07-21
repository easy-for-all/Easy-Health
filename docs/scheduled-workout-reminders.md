# Scheduled Workout Reminders

## Objetivo

`scheduled_workout_reminder_due` e emitido pelo Rails 30 minutos antes do
horario fixo de treino informado no onboarding. O Rails so registra o fato em
`user_events`; Make escolhe a copy e chama o endpoint tecnico de push.

Fluxo:

```text
cron */5 -> scheduled_workout_reminders:run
-> ScheduledWorkoutReminderSchedulerJob
-> ScheduledWorkoutReminderEligibility
-> RelationshipEventTracker
-> user_events
-> MakeWebhookDeliveryJob
-> MakeWebhookClient
-> Make
```

## Fontes De Dados

- Horario preferencial: `health_profiles.preferred_workout_time`.
- Periodo preferencial: `health_profiles.preferred_workout_period`.
- "Meu horario varia": `preferred_workout_period = "variable"`; controllers limpam `preferred_workout_time`.
- Timezone: `users.time_zone`; esta feature nao aplica fallback silencioso.
- Plano atual: `User#active_workout_plan`.
- Treino especifico no payload: primeiro `workout_days.id` do plano ativo por `COALESCE(position, day_of_week)`.
- Conclusao valida: `workout_sessions.status = "completed"` e `completion_status = "completed"`.
- Push autorizado: `user_notification_preferences.push_enabled = true`, `workout_reminders_enabled = true`, e ao menos um `device_tokens.active` com `permission_status = "granted"`.

## Regras

- Campanha real: `first_workout_scheduled_reminder_v1`.
- Evento: `scheduled_workout_reminder_due`.
- Maximo: 3 eventos registrados por usuario e plano ativo.
- Idempotencia real:
  `scheduled-workout-reminder:v1:user:{user_id}:plan:{plan_id}:date:{reminder_local_date}`.
- A unicidade e garantida pelo indice existente em
  `user_events(user_id, event_name, idempotency_key)`.
- `reminder_local_date` e a data local em que o lembrete e emitido. Exemplo:
  treino `00:15` gera lembrete `23:45` na data local anterior.
- O scheduler usa janela de 10 minutos para cron de 5 minutos:
  `reminder_at <= now` e `reminder_at > now - 10.minutes`.
- Se o plano foi criado depois do horario de lembrete do dia, a primeira
  ocorrencia valida fica para o proximo dia.

## Configuracao

```env
SCHEDULED_WORKOUT_REMINDER_ENABLED=false
MAKE_WEBHOOK_ENABLED=true
MAKE_WEBHOOK_URL=https://make.example/webhook
MAKE_WEBHOOK_SECRET=secret
MAKE_EVENT_SCHEMA_VERSION=2
MAKE_WEBHOOK_ALLOWED_EVENTS=scheduled_workout_reminder_due
MAKE_PUSH_ORCHESTRATION_ENABLED=true
```

Adicionar ao cron da VPS:

```cron
*/5 * * * * cd /path/api && bin/rails scheduled_workout_reminders:run
```

## Execucao Local

Simular um horario especifico:

```bash
SCHEDULED_WORKOUT_REMINDER_ENABLED=true \
MAKE_WEBHOOK_ENABLED=true \
MAKE_WEBHOOK_URL=https://make.example/webhook \
MAKE_WEBHOOK_SECRET=secret \
MAKE_EVENT_SCHEMA_VERSION=2 \
MAKE_WEBHOOK_ALLOWED_EVENTS=scheduled_workout_reminder_due \
bundle exec rake scheduled_workout_reminders:run \
USER_ID=123 \
NOW="2026-07-21T06:30:00-03:00"
```

Teste manual para admin, com campanha separada que nao conta para a campanha
real:

```bash
bundle exec rails "scheduled_workout_reminders:manual_test[admin@example.com]"
```

Em producao, o teste manual exige:

```env
CONFIRM_PRODUCTION_SCHEDULED_WORKOUT_REMINDER_MANUAL_TEST=true
```

## Payload Para Make

O serializer v2 adiciona `delivery.campaign` e `context.activation`:

```json
{
  "schema_version": 2,
  "event_name": "scheduled_workout_reminder_due",
  "occurred_at": "2026-07-21T09:30:00Z",
  "delivery": {
    "channels": ["push"],
    "campaign": "first_workout_scheduled_reminder_v1"
  },
  "user": {
    "id": 123,
    "timezone": "America/Sao_Paulo",
    "locale": "pt-BR"
  },
  "push": {
    "notification_type": "activation_reminder",
    "route": "/workouts/ready",
    "campaign_key": "scheduled_workout_reminder_due"
  },
  "context": {
    "activation": {
      "plan_id": 456,
      "workout_id": 789,
      "preferred_workout_time": "07:00",
      "reminder_time": "06:30",
      "reminder_local_date": "2026-07-21",
      "reminder_number": 1,
      "maximum_reminders": 3,
      "days_since_workout_created": 1,
      "first_workout_completed": false
    }
  }
}
```

## Validacao

Testes:

```bash
bundle exec rspec \
  spec/services/scheduled_workout_reminder_eligibility_spec.rb \
  spec/jobs/scheduled_workout_reminder_scheduler_job_spec.rb \
  spec/services/make/event_payload_serializer_spec.rb \
  spec/tasks/scheduled_workout_reminders_spec.rb
```

Consultas Rails:

```ruby
UserEvent.where(event_name: "scheduled_workout_reminder_due").order(created_at: :desc).limit(10)

UserEvent.where(event_name: "scheduled_workout_reminder_due")
         .where("metadata ->> 'campaign' = ?", "first_workout_scheduled_reminder_v1")
         .group("metadata #>> '{activation,reminder_number}'")
         .count
```

SQL:

```sql
select user_id,
       metadata #>> '{activation,plan_id}' as plan_id,
       metadata #>> '{activation,reminder_number}' as reminder_number,
       metadata #>> '{activation,reminder_local_date}' as local_date,
       make_delivery_status,
       created_at
from user_events
where event_name = 'scheduled_workout_reminder_due'
order by created_at desc
limit 20;
```

Skips e decisoes aparecem nos logs com prefixo `[ScheduledWorkoutReminder]` e
em `ActiveSupport::Notifications` com nomes `scheduled_workout_reminder.*`.
