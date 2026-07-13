# Activation Push — MVP (Android)

Push de ativação do **primeiro treino**: no máximo 2 notificações (1 lembrete no horário
preferido + 1 recuperação no dia seguinte), com opt-in explícito, deep link para o treino,
preferências, feedback "não gostei" e métricas no admin. Experimento treatment/control.

Tudo atrás da flag **`ACTIVATION_PUSH_ENABLED`** (default **off**). Nada dispara em
produção sem a flag ligada, sem Firebase configurado e sem opt-in do usuário.

## Arquitetura

Decisão e envio 100% no backend Rails, disparados por **cron externo no VPS** (mesmo
mecanismo dos `activation_reminders.rake`). Envio FCM **síncrono** dentro do sweep, com
status idempotente em `notification_deliveries`. O app Capacitor só registra token/permissão
e roteia o clique. **O Make não decide nem envia push.**

```
cron ─► rake push_activation:run_reminders  ─► FirstWorkoutReminderEligibilityJob  ─┐
        rake push_activation:run_recovery   ─► FirstWorkoutRecoveryEligibilityJob  ─┤ cria delivery (scheduled, idempotente)
        rake push_activation:dispatch_due   ─► DispatchDuePushJob ─► PushDispatchService ─► FirebasePushService (HTTP v1)
```

## Feature flags (ENV)

| Flag | Default | Efeito |
|---|---|---|
| `ACTIVATION_PUSH_ENABLED` | `false` | Liga elegibilidade/envio. Sem ela, nada é agendado/enviado. |
| `ACTIVATION_PUSH_EXPERIMENT_ENABLED` | `false` | Liga o split treatment/control. Off → todos treatment. |

## Secrets externos (ação manual)

**Nunca commitar** `google-services.json` nem o Service Account. Ambos entram por secret.

### 1. `GOOGLE_SERVICES_JSON_BASE64` (GitHub Actions — build Android)
Já suportado no workflow `android-internal-testing.yml`. Passos:
1. No **Firebase Console**, selecione o projeto (reuse o projeto Google Cloud da EasyHealth se já existir; **não crie um novo** sem verificar).
2. Registre o app Android **`com.EasyHealth.myapp`**. Informe os SHA-1/SHA-256 (Play + debug).
3. Baixe `google-services.json`.
4. Confirme que o arquivo contém `project_info` e um client Android para `com.EasyHealth.myapp`.
5. `base64 -w0 google-services.json` → cole em **GitHub → Settings → Secrets → `GOOGLE_SERVICES_JSON_BASE64`**.

Esse secret é o config do app Android baixado em **Project Settings → Your apps → Android**.
Não use aqui o JSON de Service Account.

### 2. `FIREBASE_SERVICE_ACCOUNT_JSON` (backend — envio FCM HTTP v1)
No ambiente do **backend** (VPS/compose), **nunca no banco/repo/log**:
1. Firebase Console → **Configurações → Contas de serviço → Gerar nova chave privada** (Service Account com permissão de FCM).
2. Disponibilize o JSON no backend via **uma** das variáveis:
   - `FIREBASE_SERVICE_ACCOUNT_JSON` = conteúdo JSON puro, **ou**
   - `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` = `base64 -w0` do JSON.
3. Opcional: `FIREBASE_PROJECT_ID` (senão é lido do próprio JSON).

O `FirebasePushService` obtém o access token OAuth2 via gem **`googleauth`** e envia pelo
endpoint `https://fcm.googleapis.com/v1/projects/<id>/messages:send`. Tokens mortos
(`UNREGISTERED`/`INVALID_ARGUMENT`) são invalidados automaticamente.

## Cron no VPS

Rodar a cada ~15 min (ajuste conforme volume):

```cron
*/15 * * * * cd /caminho/api && RAILS_ENV=production bin/rails push_activation:run_reminders  >> log/push.log 2>&1
*/15 * * * * cd /caminho/api && RAILS_ENV=production bin/rails push_activation:run_recovery   >> log/push.log 2>&1
*/15 * * * * cd /caminho/api && RAILS_ENV=production bin/rails push_activation:dispatch_due    >> log/push.log 2>&1
```

`run_reminders`/`run_recovery` só **agendam** deliveries idempotentes; `dispatch_due` envia
as que chegaram no horário. O envio respeita o timezone IANA do usuário (`users.time_zone`).

## Migrations

`db/migrate/2026071213000{0..4}`: `users.time_zone`; campos de horário em `health_profiles`;
extensão de `device_tokens` (enabled/permission_status/invalidated_at/…); tabelas
`user_notification_preferences` e `notification_deliveries`.

Rodar no servidor: `bin/rails db:migrate`.

## Modelo de dados & fontes da verdade

- **Timezone:** `users.time_zone` (IANA).
- **Quando o usuário treina:** `health_profiles.preferred_workout_period` + `preferred_workout_time` (o wizard já persiste lá). `user_notification_preferences` **não** duplica o horário.
- **Opt-in / bookkeeping:** `user_notification_preferences` (push_enabled, workout_reminders_enabled, timestamps de ativação, variante do experimento).
- **Entregas:** `notification_deliveries` (idempotency_key único; `payload_json` **nunca** contém token).

## Privacidade

Este push é **funcional** (ativação do primeiro treino), **não marketing**. Os tipos são
separados no código/modelo: operacional ≠ lembrete de treino ≠ marketing
(`users.marketing_consent` é independente). Opt-out é imediato (`workout_reminders_enabled=false`
cancela pendências). Exclusão de conta remove `device_tokens`/prefs/deliveries via
`dependent: :destroy`. Admin e logs **não** expõem tokens (mascarados). Atualize a política de
privacidade para citar: uso de notificações, token do dispositivo, preferências, métricas de
abertura/conversão e desativação.

## Analytics / eventos

Backend (`RelationshipEventTracker`, `suppress_make_delivery: true` — Make não recebe):
`push_scheduled`, `push_sent`, `push_failed`, `push_opened`, `push_deep_link_opened`,
`workout_started_from_push`, `workout_completed_from_push`, `notification_disliked`,
`notification_type_disabled`, `notification_time_changed`, `notification_skipped`.
Frontend (gtag): `push_prepermission_*`, `push_permission_*`, `push_token_*`,
`workout_time_*`. **Nunca** enviam token/e-mail/nome.

**Métrica principal (admin):** % que inicia o 1º treino ≤2h após abrir o push.
**Secundária:** % de elegíveis que iniciam até o fim do dia.

## Roteiro de validação manual

Pré-requisitos: flag ligada, Firebase configurado, build no Internal Testing.

1. **Novo usuário:** instalar → criar conta → onboarding → escolher "À noite" 19:00 → criar treino → ver pré-permissão → "Ativar lembretes" → conceder permissão Android → confirmar token no backend (`DeviceToken.active`) → `bin/rails push_activation:run_reminders` + `dispatch_due` (com `scheduled_for` no passado para teste) → receber push → tocar → abrir o treino correto → iniciar → confirmar `workout_started_from_push` e cancelamento da recuperação pendente.
2. **Agora não:** onboarding → "Agora não" → confirmar que o prompt nativo **não** abriu e que não há token ativo → ativar depois em /settings.
3. **Recuperação:** receber o 1º lembrete → não iniciar → avançar tempo → receber **apenas uma** recuperação → confirmar que não vem uma terceira (flow_completed).
4. **Não gostei:** abrir pelo push (`?from_push=<id>`) → "Não gostei deste lembrete" → "Não quero esse tipo" → confirmar `workout_reminders_enabled=false` e pendências canceladas.
5. **Horário ruim:** "Horário ruim" → ajustar em /settings → confirmar persistência e reagendamento no timezone certo.
6. **Grupo controle:** usuário elegível com variante `control` → nenhum push enviado → aparece no admin (treatment vs control).

**Não considerar concluído** apenas por token gerado ou FCM retornar sucesso: exige push
recebido, deep link abrindo o treino, preferências respeitadas, idempotência validada e o
painel admin registrando os resultados.

## Rollout

Habilitar inicialmente só para: usuários novos, Android, treino criado após o rollout,
opt-in explícito, grupo treatment. **Sem** envio retroativo à base antiga.
