# Orquestração de eventos — EasyHealth produz, Make orquestra

## O contrato em uma frase

**EasyHealth** é a fonte de verdade dos EVENTOS. **Make** é o orquestrador das
COMUNICAÇÕES. O **backend** continua sendo a autoridade dos hard gates.

```
EasyHealth detecta o fato
    ↓ cria UserEvent  (sempre — horário, preferência de push e token NÃO impedem)
    ↓ é orchestration event?  (config/communication_events.yml)
    ↓ envia 100% deles ao Make
Make decide: comunica? qual canal? qual copy? qual campanha? A/B? frequência?
    ↓ se decidir push: POST /api/v1/integrations/make/push_dispatches
EasyHealth aplica os HARD GATES (opt-out, tipo desabilitado, token, rate limit,
                                 quiet hours)
    ↓ Firebase/FCM → device
```

### Evento ≠ comunicação

Esta é a distinção que o sistema inteiro protege. "O usuário está há 3 dias sem
treinar" é verdade às 05:00 e às 15:00. Suprimir o **fato** por causa do relógio,
de um opt-out ou de um token ausente perde a informação para sempre e torna o
histórico não auditável. Restrições de comunicação pertencem ao **dispatch**,
onde são reavaliadas no instante em que importam.

---

## 1. Fonte de verdade

`api/config/communication_events.yml`.

Um evento é **orchestration event** quando tem entrada no YAML, está `enabled` e
declara ≥1 canal. Não existe chave `orchestration:` separada: a entrada já é a
declaração, e um segundo interruptor seria só mais um lugar para divergir.

| Quero… | Faça |
|---|---|
| Adicionar um evento à orquestração | Entrada no YAML (+ nome em `RelationshipEventTracker::EVENTS`) |
| Declarar que um evento NUNCA comunica | Entrada em `config/non_communication_events.yml` com `reason` |
| Desligar UM evento | `enabled: false` na entrada |
| Desligar TUDO | `MAKE_WEBHOOK_ENABLED=false` |

### Todo evento do registry precisa de uma decisão

`config/communication_events.yml` declara o que **é** orquestração;
`config/non_communication_events.yml` declara o que **deliberadamente não é**, com
o motivo (`push_telemetry`, `product_analytics`, `internal_audit`,
`legacy_inactive`, `covered_by_other_event`).

Um evento de `RelationshipEventTracker::EVENTS` que não está em **nenhum** dos
dois é `uncatalogued`: warning **crítico** no painel admin e falha no
`communication_events_registry_spec`. Não é formalidade — foi exatamente esse
estado silencioso que manteve `activation_workout_created` fora do Make por meses,
porque o painel só media eventos já catalogados. "Ninguém decidiu" deixou de ser
um estado alcançável.

`CommunicationEvents.validate!` **não** levanta erro por `uncatalogued`: derrubar
o boot em produção porque alguém adicionou um nome novo seria pior que a lacuna
que isso reporta. A cobrança acontece em CI e no painel.

`MakeWebhookEligibility.allowed_events` **deriva** dessa lista. `CommunicationEvents`
é validado no boot e, mais importante, em CI por
`spec/services/communication_events_registry_spec.rb`, que falha o build se um
evento não existir no tracker, não tiver canal, tiver canal desconhecido, for
push sem `notification_type`/`route`, tiver chave duplicada, ficar em
`orchestration_event_names` mesmo com `enabled: false`, ou não conseguir gerar
payload pelo serializer.

### `MAKE_WEBHOOK_ALLOWED_EVENTS` é legado

Já foi a allowlist. Hoje **só adiciona** eventos sem entrada no YAML, apenas fora
de produção (ou com `MAKE_WEBHOOK_ALLOW_LEGACY_ENV_EVENTS=true`, temporário e
auditável). Ele **nunca remove**, então um orchestration event não some em
silêncio. Qualquer evento presente só no env aparece como `allowlist_drift` no
painel admin — é configuração devendo ao YAML.

---

## 2. Catálogo dos orchestration events

| Evento | Produtor | Timing | Canais candidatos | Tipo | Idempotência |
|---|---|---|---|---|---|
| `activation_workout_created` | `WorkoutPlansController` | ao criar o 1º plano | push | activation | 1 por usuário/plano |
| `first_workout_not_started_2h` | `FirstWorkoutNotStarted2hJob` | ~15min; âncora 2–26h | push | activation | 1 por âncora `activation_workout_created` |
| `first_workout_not_started_24h` | `FirstWorkoutNotStarted24hJob` | ~15min; âncora 24–48h | push | activation | 1 por âncora |
| `scheduled_workout_reminder_due` | `ScheduledWorkoutReminderSchedulerJob` | ~15min; `preferred_workout_time − lead` | push | activation | 1 por usuário/plano/data local; máx. 3 por plano |
| `first_workout_completed` | `WorkoutSessionsController` | no momento da conclusão | push | progress | 1 por sessão |
| `user_inactive_3_days` | `RelationshipDailyJob` | 1×/dia | push | retention | 1 por `last_workout_at` |
| `user_inactive_7_days` | `RelationshipDailyJob` | 1×/dia | push + email | retention | 1 por `last_workout_at` |
| `user_created`, `subscription_created`, `checkout_started`, `trial_day_3`, `trial_day_6`, `trial_expired_without_subscription`, `workout_completed_partial`, `never_created_workout`, `churn_risk`, `first_workout_created`, `plan_created_but_not_used` | vários | evento de negócio | email | lifecycle/activation/retention | por chave própria |

**`user_inactive_15_days` é LEGADO e inativo.** Existe em
`RelationshipEventTracker::EVENTS` e tem context builder, mas **não** tem entrada
no YAML e não faz parte da jornada. Não reintroduzir.

`activation_workout_created` é **âncora E orchestration event**. Ele continua
sendo o ponto de partida dos lembretes 2h/24h (`FirstWorkoutNotStarted{2h,24h}Job`
leem esse `UserEvent`) e, desde ago/2026, também é entregue ao Make.

O evento em si **não envia FCM**: ele é um *signal*. O Make pode posteriormente
solicitar um push via `POST /api/v1/integrations/make/push_dispatches`, e a
EasyHealth continua sendo a autoridade final sobre consentimento, categoria,
device token, permission, cooldown, frequency cap e quiet hours.

> **Atenção ao cenário do Make.** `activation_workout_created` é
> `activation_reminder`, categoria de engagement. Um push imediato nesse evento
> consome o cooldown de 20h e faria `first_workout_not_started_2h` ser pulado com
> `cooldown_active` duas horas depois. Enquanto a interferência com a jornada
> 2h/24h não for decidida, o cenário deve receber e rotear o evento **sem push
> imediato**.

Histórico: até ago/2026 ele não tinha entrada no YAML e nascia com
`make_delivery_status=disabled` / `make_last_error=event_not_orchestration`. Como
o painel admin só consultava eventos já catalogados, a lacuna era invisível — é
por isso que hoje existe `config/non_communication_events.yml` e a métrica
`uncatalogued_events`.

---

## 3. Hard gates, separados por canal

O erro que essa separação corrige: regras de **e-mail** (consentimento de
marketing, unsubscribe, bounce) barravam eventos **push-only**.

| Gate | Onde vive | Vale para |
|---|---|---|
| Conta deletada/anonimizada | `MakeWebhookEligibility.account_valid?` | todos os canais |
| `marketing_consent`, `unsubscribed_at`, `email_bounced_at` | `MakeWebhookEligibility.email_consent_ok?` | **só e-mail** |
| `push_enabled`, `notifications_disabled_at`, tipo desabilitado, token ativo, permissão | `Make::PushDispatchRequest` | **só push, no dispatch** |
| Rate limit, cooldown, cap semanal | `Make::PushDispatchRequest` | push |
| Quiet hours | `Make::PushDispatchRequest` (atrás de flag) | push |

`deliverable_channels(user, event_name)` **estreita** os canais em vez de
suprimir o evento. Um usuário sem consentimento de e-mail recebe
`user_inactive_7_days` com `channels: ["push"]`. Nenhuma proteção de
consentimento de e-mail foi reduzida.

### `candidate_channels` vs `channels` no payload

Duas perguntas diferentes, dois arrays diferentes:

| Campo | Pergunta que responde | Origem |
|---|---|---|
| `delivery.candidate_channels` | o que o **catálogo** permite ao Make considerar | `CommunicationEvents.channels_for` — igual para todo usuário |
| `delivery.channels` | o que a EasyHealth **decidiu expor** neste evento, após o channel routing | `MakeWebhookEligibility.deliverable_channels`, o mesmo valor persistido em `make_delivery_channels` |

`channels` **não** significa "entregável agora". Falta de device token,
`push_enabled=false` e permissão não concedida **nunca** removem push de nenhum
dos dois arrays — isso é *push delivery eligibility*, aplicada depois por
`Make::PushDispatchRequest`. O único gate que estreita um canal nessa camada é o
de **e-mail**, porque o Make envia e-mail direto e nenhum callback da EasyHealth
consegue reaplicar a regra depois.

Quem resolve os canais é `MakeWebhookClient#channels_for` (override de smoke test
→ `make_delivery_channels` persistido → recálculo para linhas legadas). O
`Make::EventPayloadSerializer` permanece um formatador puro e não consulta
elegibilidade — foi essa consulta ausente que fazia payload e banco discordarem.

O Make **não consegue furar** um opt-out: ele só pede; quem envia é o backend.

---

## 4. Quiet hours e o contrato `deferred`

Quiet hours (22:00–07:00 local) **não** impede o evento de nascer. No dispatch, com
`PUSH_QUIET_HOURS_ENABLED=true`:

```json
{ "status": "deferred", "sent": false, "defer_reason": "quiet_hours",
  "deferred": true,
  "next_allowed_at": "2026-08-15T07:00:00-03:00",
  "user_timezone": "America/Sao_Paulo",
  "dispatch_id": 123, "correlation_id": "make-456" }
```

`deferred` distingue "não pode agora" de "não pode nunca". Não é `skipped` e não
usa `skip_reason`: o backend guarda a decisão/copy/campanha em `PushDispatch` e
um sweep próprio libera depois de `next_allowed_at`. Skips continuam terminais
(`global_opt_out`, `no_active_token`, `stale_after_quiet_hours`, etc.).

Para `scheduled_workout_reminder_due` existem **dois** motivos distintos, que não
devem ser confundidos:

- `stale_scheduled_reminder` — no momento da tentativa o `current_time` já é
  igual ou posterior ao `activation.target_workout_at`. O conteúdo perdeu a
  validade; nem redrive, nem retry, nem release de deferred pode chegar ao FCM.
- `stale_after_quiet_hours` — o push ainda é válido agora, mas o **fim** de quiet
  hours cairia igual ou depois do `target_workout_at`, então adiar não adianta.

Dentro da janela explícita `activation.reminder_due_at → target_workout_at` esse
lembrete atravessa quiet hours em vez de ser adiado: o horário foi escolhido pelo
usuário. Fora dela, quiet hours vale normalmente. Detalhes em
`docs/scheduled-workout-reminders.md`.

---

## 5. `origin_surface` — origem ≠ canal

`user_events.origin_surface` responde **qual superfície produziu ESTE evento**:
`android`, `web`, `backend_scheduler`, `admin`, ou NULL (lido como `unknown`).

Não confundir com canal (`push`/`email`/…), que é por onde a comunicação pode
sair. São dimensões diferentes e o admin as exibe separadas.

Um evento derivado por scheduler é `backend_scheduler` **mesmo que a âncora tenha
vindo do Android**. Para não perder o contexto da jornada, o evento derivado
carrega em metadata `anchor_event_id` e `anchor_origin_surface`. Assim dá para
responder "quem produziu?" e "qual a origem da jornada?" sem misturar conceitos.

A origem do cliente vem do header `X-Platform`, parseado por
`Observability::Headers.platform`, que valida contra uma allowlist e **descarta**
valor hostil. **Nunca inferir plataforma por device token** — token prova
capacidade de receber push, não origem da ação. Histórico fica NULL; não há
backfill inventado.

---

## 6. Pipeline e correlação

```
UserEvent.id
  → make_attempts_count / make_first_attempt_at / make_delivery_status / make_last_http_status
  → make_execution_id (callback do Make)
  → PushDispatch.user_event_id        ← FK real
  → PushDispatch.status / skip_reason / correlation_id
  → resultado do provider
```

A correlação usa **`push_dispatches.user_event_id`**, resolvido do `event_id` que
o Make devolve, **escopado ao mesmo usuário** (um id de outra pessoa não
correlaciona). Fallback documentado: `correlation_id` no formato histórico
`make-<id>`.

**`campaign_key` não é chave relacional.** Ele nomeia a campanha e a copy, que o
Make versiona livremente (`first-workout-completed-v1`), então serve como
dimensão de relatório e nada mais.

### `sent_to_make`

Definido em `UserEvent::SENT_TO_MAKE_SQL`, propositalmente tolerante: as colunas
`make_*` foram preenchidas por códigos diferentes ao longo do tempo, e testar uma
só sub-contaria o histórico. Registros novos gravam todas de forma coerente;
**não há backfill**.

### Payload inválido é erro, não skip

`IncompleteEventError` (contexto obrigatório ausente) leva **1 retry** — para
cobrir a corrida entre `perform_later` e o commit da transação com o adapter
`:async` — e depois vira **`dead_letter`** com
`make_last_error = "missing_required_context"` e log `make_event_contract_failed`.
Nunca `skipped`: é falha de contrato e o admin marca como CRITICAL.

---

## 7. Payload para o Make (schema 2, aditivo)

`schema_version` continua **2**. Nada foi renomeado ou removido.

```json
{
  "schema_version": 2,
  "event_id": 123,
  "event_name": "scheduled_workout_reminder_due",
  "occurred_at": "2026-08-15T09:30:00Z",
  "source": "easyhealth_backend",
  "origin_surface": "backend_scheduler",
  "environment": "production",
  "delivery": {
    "channels": ["push"],
    "candidate_channels": ["push"],
    "communication_type": "activation",
    "notification_type": "activation_reminder",
    "route": "/workouts/ready",
    "engagement": true,
    "campaign": "first_workout_scheduled_reminder_v1"
  },
  "user": { "id": 123, "timezone": "America/Sao_Paulo", "locale": "pt-BR" },
  "push":  { "notification_type": "activation_reminder", "route": "/workouts/ready",
             "campaign_key": "scheduled_workout_reminder_due" },
  "context": {
    "activation": {
      "plan_id": 45, "workout_id": 88,
      "preferred_workout_time": "07:00", "reminder_time": "06:30",
      "reminder_due_at": "2026-08-15T09:30:00Z", "reminder_lead_minutes": 30,
      "detected_at": "2026-08-15T09:44:00Z", "timezone": "America/Sao_Paulo",
      "reminder_local_date": "2026-08-15", "reminder_number": 1
    }
  }
}
```

**Compatibilidade:** `delivery.channels` continua sendo o campo que o cenário Make
filtra hoje (`contains push`). `candidate_channels` responde outra pergunta — ver
[`candidate_channels` vs `channels`](#candidate_channels-vs-channels-no-payload).
`notification_type`/`route` foram espelhados em `delivery` sem esvaziar o bloco
`push`.

---

## 8. Schedulers

| Processo | Cadência | Entry point | Heartbeat |
|---|---|---|---|
| 2h / 24h / lembrete de horário | ~15min | `bin/rails orchestration:run_15min` | 3 chaves, 15min |
| Jornada diária | 1×/dia (08:00 America/Sao_Paulo) | `bin/rails orchestration:relationship_daily` | `relationship_daily_job`, 1d |
| Retry Make pending | ~15min | `bin/rails orchestration:retry_pending_make` | `make_pending_retry`, 15min |
| Push Make deferido | ~15min | `bin/rails orchestration:dispatch_deferred_pushes` | `push_dispatch_deferred`, 15min |

Cada produtor roda isolado dentro do `run_15min`: um erro não silencia os outros.
Cada job anexa `candidates_found` / `events_created` ao **seu único** heartbeat —
`ObservabilityInstrumented` faz `started! → succeeded!(metadata)`, uma escrita por
execução; um job jamais deve chamar `succeeded!` por conta própria.

### Instalação do cron

```bash
# 1. SEMPRE revisar o diff primeiro (DRY_RUN é o default)
scripts/cron/install_cron.sh

# 2. Aplicar. Linhas legacy reconhecidas da EasyHealth são migradas
#    automaticamente; refresh_analytics e crons externos são preservados.
APPLY=1 scripts/cron/install_cron.sh
```

O bloco gerenciado fica entre `# BEGIN EASYHEALTH ORCHESTRATION` e
`# END EASYHEALTH ORCHESTRATION`. Tudo fora dele é preservado byte a byte.
Logs ficam em `logs/` no projeto. O instalador usa `CRON_TZ=America/Sao_Paulo`
quando detectado; caso contrário, registra fallback técnico em UTC mantendo o
horário de negócio como 08:00 São Paulo.

---

## 9. O lembrete de horário preferido

Regra de produto:

```
reminder_due_at = preferred_workout_time − lead_time   (no timezone do usuário)
```

`lead_time` vem de `SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES` (default 30, 5–180).

A janela do scheduler (`DEFAULT_WINDOW = 20min`) é **tolerância**, não parte da
regra: a detecção é `due_at <= now AND due_at > now − janela`, então **nunca
dispara adiantado**. Treino às 07:10 ⇒ due 06:40 ⇒ o tick das 06:30 não gera e o
das 06:45 gera com 5 minutos de atraso. A janela só precisa cobrir o intervalo do
cron (15min), senão um instante due cai entre dois ticks e se perde. Timezone e
DST via `ActiveSupport::TimeZone`, sem cálculo manual de offset.

O evento carrega `reminder_due_at`, `detected_at` e `target_workout_at`: a
diferença entre os dois primeiros é o atraso do cron; o último é o horário alvo
determinístico usado para descartar lembrete obsoleto depois de quiet hours.

---

## 10. Catch-up de inatividade

Um usuário 10 dias parado, sem nenhum dos eventos registrados, gera **os dois**
thresholds na mesma execução — ambos foram genuinamente cruzados, e o Make decide
se comunica sobre os dois. Isso é explícito na metadata, não implícito:

```json
{ "days_since_last_workout": 10, "threshold_days": 3,
  "threshold_crossed_at": "2026-08-07T...", "detected_at": "2026-08-14T...",
  "catchup": true }
```

`catchup: true` avisa o admin de que o evento **não** ocorreu naquele instante.

---

## 11. Admin — Eventos & Comunicações

`/admin/events-communications` (backend: `GET /api/v1/admin/analytics/event_orchestration`).

Só observabilidade. Copy e campanha continuam no Make; o admin não vira CMS.

- **Funil**: gerados → enviados → aceitos, com taxas como numerador/denominador (denominador zero vira `—`, nunca `0%`).
- **Cobertura**: `all_events_generated`, `orchestration_expected`, `orchestration_sent`, `orchestration_not_sent`, `orchestration_coverage_pct`, `analytics_only_events`, `uncatalogued_events`. Existe porque "182 gerados / 33 aceitos / 0 erro" parecia saudável enquanto um evento que devia ir ao Make era arquivado com `event_not_orchestration` — o denominador só continha eventos já catalogados. Evento `analytics_only` **nunca** conta como falha de cobertura; `uncatalogued` é crítico.
- **`not_sent_breakdown`**: por que cada evento não foi enviado, agrupado por **causa**, não por status. Vários motivos compartilham `make_delivery_status='disabled'` e só `make_last_error` os distingue: `event_not_orchestration`, `no_deliverable_channel`, `webhook_disabled`, `suppressed`, `user_deleted_or_anonymized`, `pending`, `retrying`, `failed`, `dead_letter`, `skipped`, `disabled_without_reason`.
- **Por evento**: o pipeline inteiro por linha, com push correlacionado pela FK.
- **Canais candidatos** vs **Resultado do push**: blocos separados de propósito. Candidato = elegível (um evento push+email conta nos dois); resultado = o que foi pedido e o que o provider fez. WhatsApp e in-app aparecem como categoria conhecida com zero e rótulo "sem evento configurado" — sem integração fictícia.
- **Por origem**: `origin_surface`, nunca misturado com canal.
- **Schedulers**: status, último sucesso, candidatos e eventos criados.
- **Eventos recentes**: a tabela de debug — evento, origem, status Make, HTTP, dispatch, status do push, `defer_reason`/`next_allowed_at` ou motivo de skip, tudo em uma linha.
- **Alertas**: `orchestration_event_unserializable`, `orchestration_event_dead_letter`, `orchestration_event_disabled` (anormal salvo razão prevista ou webhook globalmente off), `scheduler_stale`, `zero_push_to_make`, `zero_provider_accepted`, `allowlist_drift`, `uncatalogued_event` (**crítico**: evento do registry sem decisão em nenhum catálogo), `heartbeat_missing`.

Diagnóstico por CLI: `bin/rails orchestration:status`.

---

## 12. Rollout do `scheduled_workout_reminder_due`

1. Deploy do código.
2. `bin/rails db:migrate`.
3. Healthcheck OK.
4. `scripts/cron/install_cron.sh` (DRY_RUN) → revisar diff → `APPLY=1`.
5. `bin/rails orchestration:status`: conferir timezone default, daily 08:00 São Paulo, schedulers 15min, lead 30 e quiet hours 22:00–07:00.
6. `bin/rails "communication_events:preview[scheduled_workout_reminder_due,<email>]"` para conferir o payload.
7. Configurar/validar o cenário no Make (filtro `delivery.channels contains push`).
8. Validar com um usuário de teste cujo `preferred_workout_time` esteja ~40min à frente.
9. Observar o painel (Eventos recentes + Schedulers) e os logs por 24h.
10. Liberar geral.

Rollback de qualquer etapa: voltar a flag para `false`.

`PUSH_QUIET_HOURS_ENABLED=true` não exige que Make reagende: o backend mantém e
libera `PushDispatch deferred`.

---

## 13. Queries SQL de validação

```sql
-- Eventos de orquestração nas últimas 24h: gerados, usuários, enviados, aceitos
SELECT event_name,
       COUNT(*) AS generated,
       COUNT(DISTINCT user_id) AS unique_users,
       COUNT(*) FILTER (WHERE make_attempts_count > 0
                           OR make_first_attempt_at IS NOT NULL
                           OR make_last_attempt_at IS NOT NULL
                           OR make_delivered_to_provider_at IS NOT NULL
                           OR make_delivery_status = 'accepted_by_make') AS sent_to_make,
       COUNT(*) FILTER (WHERE make_delivery_status = 'accepted_by_make') AS accepted_by_make
FROM user_events
WHERE created_at > NOW() - INTERVAL '24 hours'
  AND event_name IN ('first_workout_not_started_2h','first_workout_not_started_24h',
                     'scheduled_workout_reminder_due','first_workout_completed',
                     'user_inactive_3_days','user_inactive_7_days')
GROUP BY event_name ORDER BY generated DESC;

-- Mesma coisa em 7 dias: troque para INTERVAL '7 days'.

-- Por origem
SELECT COALESCE(origin_surface,'unknown') AS origin_surface,
       COUNT(*) AS events, COUNT(DISTINCT user_id) AS unique_users
FROM user_events
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY 1 ORDER BY events DESC;

-- Pipeline completo, correlacionado pela FK (nunca por campaign_key)
SELECT ue.event_name,
       COUNT(DISTINCT ue.id) AS generated,
       COUNT(DISTINCT ue.id) FILTER (WHERE ue.make_delivery_status = 'accepted_by_make') AS accepted_by_make,
       COUNT(pd.id) AS push_requested,
       COUNT(pd.id) FILTER (WHERE pd.status IN ('provider_accepted','partially_accepted','opened')) AS provider_accepted,
       COUNT(pd.id) FILTER (WHERE pd.status = 'failed')  AS provider_rejected,
       COUNT(pd.id) FILTER (WHERE pd.status = 'skipped') AS skipped
FROM user_events ue
LEFT JOIN push_dispatches pd ON pd.user_event_id = ue.id
WHERE ue.created_at > NOW() - INTERVAL '7 days'
GROUP BY ue.event_name ORDER BY generated DESC;

-- Por que os pushes foram ignorados
SELECT skip_reason, COUNT(*) FROM push_dispatches
WHERE created_at > NOW() - INTERVAL '7 days' AND status = 'skipped'
GROUP BY skip_reason ORDER BY count DESC;

-- Schedulers vivos?
SELECT key, last_succeeded_at, consecutive_failures, metadata
FROM observability_heartbeats
WHERE key IN ('first_workout_not_started_2h','first_workout_not_started_24h',
              'scheduled_workout_reminder','relationship_daily_job')
ORDER BY key;
```

---

## 14. Fora de escopo

Integração WhatsApp real, novo provedor de push, iOS, sistema de campanhas
próprio, editor de mensagens, data warehouse, Kafka, Redis/Sidekiq, event
streaming, backfill histórico, refatoração geral de analytics.

## Ver também

- `docs/make-event-contract.md` — contrato do payload
- `docs/push-journey-v1.md` — jornada de push
- `docs/scheduled-workout-reminders.md` — lembrete de horário
- `docs/make-push-orchestration.md` — endpoint de dispatch
- `docs/observability/RUNBOOK.md` — operação
