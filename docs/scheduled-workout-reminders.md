# Scheduled Workout Reminders

## Objetivo

`scheduled_workout_reminder_due` e emitido pelo Rails 30 minutos antes do
horario fixo de treino informado no onboarding. O Rails so registra o fato em
`user_events`; Make escolhe a copy e chama o endpoint tecnico de push.

Fluxo:

```text
cron */15 -> orchestration:run_15min
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
- Timezone: `CommunicationTime.zone_for(user)`; preferencia de notificacao vence,
  depois `users.time_zone`, depois instalacao Android vinculada se aplicavel, e
  fallback `America/Sao_Paulo`.
- Plano atual: `User#active_workout_plan`.
- Treino especifico no payload: primeiro `workout_days.id` do plano ativo por `COALESCE(position, day_of_week)`.
- Conclusao valida: `workout_sessions.status = "completed"` e `completion_status = "completed"`.
- Push autorizado: decidido depois, em `Make::PushDispatchRequest`.

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
- Regra de produto: `reminder_due_at = preferred_workout_time - lead_time`, com
  `lead_time` em `SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES` (default 30).
- A janela de 20 minutos e TOLERANCIA do scheduler, nao parte da regra:
  `reminder_due_at <= now` e `reminder_due_at > now - 20.minutes`. Nunca dispara
  adiantado; so pega um alvo que JA ficou due. Precisa ser >= o intervalo do
  cron (15min), senao um instante due cai entre dois ticks e se perde.
  Treino 07:10 => due 06:40 => tick 06:30 nao gera, tick 06:45 gera 5min tarde.
- Elegibilidade so bloqueia por regra de NEGOCIO (plano, horario,
  treino concluido, maximo, ja enviado hoje). `push_disabled`, ausencia de
  token e allowlist do Make NAO impedem o evento: sao decididos no dispatch.
- O evento persiste `activation.target_workout_at`, calculado no momento em que
  o fato nasce. Esse valor, e nao uma preferencia futura do usuario, decide se
  um push deferido por quiet hours ficou obsoleto.
- Se o plano foi criado depois do horario de lembrete do dia, a primeira
  ocorrencia valida fica para o proximo dia.

## Configuracao

```env
COMMUNICATION_DEFAULT_TIMEZONE=America/Sao_Paulo
SCHEDULED_WORKOUT_REMINDER_ENABLED=true
MAKE_WEBHOOK_ENABLED=true
MAKE_WEBHOOK_URL=https://make.example/webhook
MAKE_WEBHOOK_SECRET=secret
MAKE_EVENT_SCHEMA_VERSION=2
MAKE_PUSH_ORCHESTRATION_ENABLED=true
SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES=30
```

`MAKE_WEBHOOK_ALLOWED_EVENTS` nao e mais necessario: a fonte de verdade e
`config/communication_events.yml`, que ja lista `scheduled_workout_reminder_due`.

Cron: instalado pelo bloco versionado, nunca a mao.

```bash
scripts/cron/install_cron.sh            # DRY RUN, mostra o diff
APPLY=1 scripts/cron/install_cron.sh    # aplica
```

Rollout completo em `docs/event-orchestration.md`.

## Execucao Local

Simular um horario especifico:

```bash
SCHEDULED_WORKOUT_REMINDER_ENABLED=true \
MAKE_WEBHOOK_ENABLED=true \
MAKE_WEBHOOK_URL=https://make.example/webhook \
MAKE_WEBHOOK_SECRET=secret \
MAKE_EVENT_SCHEMA_VERSION=2 \
MAKE_WEBHOOK_ALLOWED_EVENTS=scheduled_workout_reminder_due \
bin/rails scheduled_workout_reminders:run \
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
