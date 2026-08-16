# Push Journey V1 — eventos de push (Make orquestra a copy)

Jornada de push simplificada. **Família A (Make) é o único caminho ativo**; a
Família B interna (`NotificationDelivery` + `PushDispatchService` + cron
`push_activation:*`) está desativada (código preservado para rollback).

## Fluxo

```
Rails detecta o FATO (cron 15min / controller) — sem filtro de horário
 → cria UserEvent uma vez  → push_event_eligible
 → webhook v2 assinado → Make               → push_requested_to_make
 → Make escolhe title/body pelo event_name e chama:
   POST /api/v1/integrations/make/push_dispatches
 → Rails valida consentimento + FREQUÊNCIA + token + rota + idempotência
 → FCM                                        → push_provider_accepted | push_dispatch_skipped
 → app abre (dispatch_id) → opened_at         → push_opened
 → atribuição ≤24h após open                  → workout_started/completed_after_push
```

## Os eventos com canal push

Config técnica em [api/config/communication_events.yml](../api/config/communication_events.yml)
(fonte única). **A copy (título/corpo/emoji) vive no cenário do Make**, não no Rails.

| event_name | Gatilho (Rails re-checa a condição viva) | channels | notification_type | route | engagement |
| --- | --- | --- | --- | --- | --- |
| `activation_workout_created` | 1º plano criado (**signal**, não push imediato) | push | activation_reminder | /workouts/ready | sim |
| `first_workout_not_started_2h` | ≥2h do 1º plano, sem sessão iniciada | push | activation_reminder | /workouts/ready | sim |
| `first_workout_not_started_24h` | ≥24h do 1º plano, sem iniciar | push | activation_reminder | /workouts/ready | sim |
| `first_workout_completed` | conclusão real do 1º treino (1x) | push | progress_update | /workouts | não |
| `user_inactive_3_days` | ≥1 conclusão e ≥3 dias sem concluir | push | workout_reminder | /workouts/ready | sim |
| `user_inactive_7_days` | ≥7 dias sem concluir | push, email | workout_reminder | /workouts/ready | sim |

- Atividade = `workout_sessions.maximum(:completed_at)` (não login/abertura).
- Emissão: jobs `FirstWorkoutNotStarted2hJob`/`24hJob` (`bin/rails orchestration:run_15min`),
  inatividade em `RelationshipDailyJob` (`bin/rails orchestration:relationship_daily`),
  conclusão em `WorkoutSessionsController`.
- Cancelamento = **não emitir quando a condição falha** + idempotência (sem sinal Rails→Make).
- Janela de silêncio: **não** bloqueia a geração do evento. `PushQuietHours` só
  atua no dispatch, atrás de `PUSH_QUIET_HOURS_ENABLED`. Durante 22:00–07:00,
  o backend persiste `PushDispatch status=deferred` com `next_allowed_at` e o
  sweep backend libera depois. Não depende de o Make chamar novamente.
  Ver `docs/event-orchestration.md`.

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

> ⚠️ **Armadilha de smoke test.** `first_workout_completed` é `progress_update`, que
> é isento de **duas** portas: a frequência acima **e** o opt-out de categoria
> (`workout_reminders_enabled`, que vale só para `workout_reminder` e
> `activation_reminder`). Logo, "o completed chegou" **não** prova que a config de
> push do usuário está boa — os outros 4 eventos podem estar sendo barrados por
> `category_opt_out` ou `cooldown_active`. Diagnostique com
> `rake push_journey:diagnose[email]` antes de mexer no body do Make.

## Bypass de smoke test (produção)

Permite validar o pipeline **real** (`UserEvent → Make → push_dispatches →
PushDispatch → FCM → Android`) sem esperar o relógio. **Só regras de tempo são
dispensadas**, e cada uma é pedida separadamente:

| Flag no `data` | O que dispensa |
| --- | --- |
| `bypass_engagement_frequency` | cooldown de 20h + cap de 2/7 dias |
| `bypass_quiet_hours` | o adiamento (`deferred`) dentro de 22:00–07:00 |

**Nunca** são dispensados: consentimento (`push_enabled`), opt-out de categoria,
permissão do device, token ativo, allowlist de rota, validação de payload,
idempotência, Firebase configurado e a autenticação do endpoint.

### Credencial compartilhada

As duas flags usam a **mesma** credencial. Todas as condições precisam valer ao
mesmo tempo:

| # | Condição |
| --- | --- |
| 1 | `data.source == "manual_push_test"` |
| 2 | `MAKE_PUSH_TEST_BYPASS_ENABLED=true` no ambiente |
| 3 | header `X-Push-Test-Token` batendo com `MAKE_PUSH_TEST_BYPASS_TOKEN` |
| 4 | usuário-alvo é `admin` **e** está em `MAKE_PUSH_TEST_BYPASS_EMAILS` |
| 5 | a flag correspondente presente e `true` no `data` |

A allowlist é **fail-closed**: `MAKE_PUSH_TEST_BYPASS_EMAILS` vazio nega todo
bypass, mesmo com `ENABLED=true` e token correto. Não existe default hardcoded.

O token do header é **separado** do Bearer de dispatch: o cenário de produção do
Make tem só o Bearer, então nunca consegue um bypass mesmo que alguém edite o
body. O `X-Push-Test-Token` só deve ser enviado pelo branch de smoke test do
cenário, nunca nas chamadas normais.

Toda tentativa — concedida ou negada, inclusive `source` inválido — gera **um**
registro no log e em `user_events`:

| Caso | Evento |
| --- | --- |
| só `bypass_engagement_frequency` | `push_frequency_bypass_granted` / `_denied` |
| envolve `bypass_quiet_hours` | `push_test_bypass_granted` / `_denied` |

Metadata: `admin`, `bypass_engagement_frequency`, `bypass_quiet_hours`,
`notification_type`, `campaign_key`, `correlation_id`, `denied_reason`
(`invalid_source`, `bypass_disabled_for_env`, `invalid_test_token`,
`user_not_allowlisted`). Nenhum token FCM, header de teste ou Bearer é logado.

As flags são removidas do `data` antes do envio ao FCM — plumbing de teste não
chega ao device. `source` chega ao app sempre como `"make"`.

### Procedimento em produção

```env
# Antes do teste (no .env da VPS):
MAKE_PUSH_TEST_BYPASS_ENABLED=true
MAKE_PUSH_TEST_BYPASS_TOKEN=<openssl rand -hex 32, diferente do MAKE_PUSH_DISPATCH_TOKEN>
MAKE_PUSH_TEST_BYPASS_EMAILS=mail.marcus.reis@gmail.com

# Depois do teste:
MAKE_PUSH_TEST_BYPASS_ENABLED=false
```

Com `ENABLED=false` o mecanismo fica inerte; não é obrigatório remover `TOKEN` e
`EMAILS`. **Nunca** desligar `PUSH_QUIET_HOURS_ENABLED` nem alterar a janela
22:00–07:00 para testar — é exatamente isso que o bypass evita.

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

Uma rota por `event_name`. Cada rota: filtro `2.event_name = <evento>` → módulo HTTP
com o body acima (title/body **fixos no cenário**, um por evento). Bearer =
`MAKE_PUSH_DISPATCH_TOKEN`. `user_inactive_7_days` mantém também a branch de e-mail.
Error Handler: retry em 502/429; ignorar 401/422.

**`activation_workout_created` precisa ser aceito sem erro antes do deploy do
backend**, ainda que a rota faça no-op. Ele é *signal*: por ser
`activation_reminder` (engagement), um push imediato consome o cooldown de 20h e
faria `first_workout_not_started_2h` ser pulado com `cooldown_active`. Roteie e
registre; só decida sobre push imediato depois de resolver essa interferência.

## Analytics (funil por evento no admin)
`push_event_eligible` → `push_requested_to_make` → `push_provider_accepted` →
`push_opened` → `workout_started_after_push` → `workout_completed_after_push`;
skips via `push_dispatch_skipped`. Atribuição só após `push_opened`, janela 24h.
