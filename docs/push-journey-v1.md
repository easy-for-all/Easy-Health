# Push Journey V1 — 5 eventos (Make orquestra a copy)

Jornada de push simplificada. **Família A (Make) é o único caminho ativo**; a
Família B interna (`NotificationDelivery` + `PushDispatchService` + cron
`push_activation:*`) está desativada (código preservado para rollback).

## Fluxo

```
Rails detecta elegibilidade (cron 15min / controller) + janela 08–21 local
 → cria UserEvent uma vez  → push_event_eligible
 → webhook v2 assinado → Make               → push_requested_to_make
 → Make escolhe title/body pelo event_name e chama:
   POST /api/v1/integrations/make/push_dispatches
 → Rails valida consentimento + FREQUÊNCIA + token + rota + idempotência
 → FCM                                        → push_provider_accepted | push_dispatch_skipped
 → app abre (dispatch_id) → opened_at         → push_opened
 → atribuição ≤24h após open                  → workout_started/completed_after_push
```

## Os 5 eventos

Config técnica em [api/config/communication_events.yml](../api/config/communication_events.yml)
(fonte única). **A copy (título/corpo/emoji) vive no cenário do Make**, não no Rails.

| event_name | Gatilho (Rails re-checa a condição viva) | channels | notification_type | route | engagement |
| --- | --- | --- | --- | --- | --- |
| `first_workout_not_started_2h` | ≥2h do 1º plano, sem sessão iniciada | push | activation_reminder | /workouts/ready | sim |
| `first_workout_not_started_24h` | ≥24h do 1º plano, sem iniciar | push | activation_reminder | /workouts/ready | sim |
| `first_workout_completed` | conclusão real do 1º treino (1x) | push | progress_update | /workouts | não |
| `user_inactive_3_days` | ≥1 conclusão e ≥3 dias sem concluir | push | workout_reminder | /workouts/ready | sim |
| `user_inactive_7_days` | ≥7 dias sem concluir | push, email | workout_reminder | /workouts/ready | sim |

- Atividade = `workout_sessions.maximum(:completed_at)` (não login/abertura).
- Emissão: jobs `FirstWorkoutNotStarted2hJob`/`24hJob` (rake `push_journey:*`),
  inatividade em `RelationshipDailyJob`, conclusão em `WorkoutSessionsController`.
- Cancelamento = **não emitir quando a condição falha** + idempotência (sem sinal Rails→Make).
- Janela de silêncio: `PushQuietHours.allowed?` (08–21 local, fallback America/Sao_Paulo).

## Copy sugerida (configurar no Make)

- 2h: "Seu primeiro treino está esperando ⏰" / "Começar com 10 minutos já conta."
- 24h: "Vamos começar sem pressão?" / "Faça o primeiro exercício e veja como se sente."
- completed: "Primeiro treino concluído 🎉" / "Você começou. Agora o objetivo é construir consistência."
- inactive_3: "Bora retomar? 👟" / "Um treino curto já ajuda você a voltar ao ritmo."
- inactive_7: "Seu plano continua por aqui 💙" / "Volte com um treino leve e retome no seu ritmo."

## Payload Rails → Make (schema v2)

Nunca contém `title`, `body` nem token FCM.

```json
{
  "schema_version": 2,
  "event_name": "first_workout_not_started_2h",
  "event_id": "12345",
  "occurred_at": "2026-07-19T15:00:00Z",
  "user": { "id": 13, "email": "...", "timezone": "America/Sao_Paulo" },
  "delivery": { "channels": ["push"] },
  "push": { "notification_type": "activation_reminder", "route": "/workouts/ready", "campaign_key": "first_workout_not_started_2h" },
  "context": { "first_workout_created_at": "...", "hours_since_creation": 2, "total_workouts_completed": 0 }
}
```
`user_inactive_7_days` → `"delivery": { "channels": ["push", "email"] }`.

## Payload Make → dispatch

```json
{
  "event_id": "{{2.event_id}}",
  "campaign_key": "{{2.event_name}}",
  "user_id": "{{2.user.id}}",
  "notification_type": "{{2.push.notification_type}}",
  "title": "Seu primeiro treino está esperando ⏰",
  "body": "Começar com 10 minutos já conta.",
  "route": "{{2.push.route}}",
  "data": { "source": "make", "event_name": "{{2.event_name}}" }
}
```

## Frequência (aplicada no dispatch, reusa `push_dispatches`)

- Máx **2** pushes de engajamento em janela móvel de **7 dias** → skip `frequency_capped`.
- Cooldown mínimo **20h** entre engajamentos → skip `cooldown_active`.
- Engajamento = `activation_reminder`, `workout_reminder`. **`progress_update`
  (first_workout_completed), `transactional`, `account_security` são isentos.**

## Config manual — VPS (.env)

```env
MAKE_EVENT_SCHEMA_VERSION=2
MAKE_WEBHOOK_ALLOWED_EVENTS=first_workout_not_started_2h,first_workout_not_started_24h,first_workout_completed,user_inactive_3_days,user_inactive_7_days
ACTIVATION_PUSH_ENABLED=false
MAKE_PUSH_ORCHESTRATION_ENABLED=true
MAKE_PUSH_DISPATCH_TOKEN=<segredo>
```
`MAKE_WEBHOOK_ALLOWED_EVENTS` é só proteção operacional; a fonte técnica é o YAML.

### Cron (a cada 15min)
Adicionar:
```
*/15 * * * * ... bin/rails push_journey:first_workout_not_started_2h
*/15 * * * * ... bin/rails push_journey:first_workout_not_started_24h
```
Manter o job diário de relacionamento (inatividade) num horário comercial (BRT).
**Remover** os crons antigos: `push_activation:run_reminders`, `run_recovery`, `dispatch_due`.

## Config manual — Make

5 rotas por `event_name`. Cada rota: filtro `2.event_name = <evento>` → módulo HTTP
com o body acima (title/body **fixos no cenário**, um por evento). Bearer =
`MAKE_PUSH_DISPATCH_TOKEN`. `user_inactive_7_days` mantém também a branch de e-mail.
Error Handler: retry em 502/429; ignorar 401/422.

## Analytics (funil por evento no admin)
`push_event_eligible` → `push_requested_to_make` → `push_provider_accepted` →
`push_opened` → `workout_started_after_push` → `workout_completed_after_push`;
skips via `push_dispatch_skipped`. Atribuição só após `push_opened`, janela 24h.
