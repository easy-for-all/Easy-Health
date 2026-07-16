# Push Notifications — Relatório de Bateria de Testes

_Gerado em 2026-07-15 · branch `ajuste-fluxo-web-74` · autor da bateria: assistente (a pedido de Marcus)._

> **Escopo:** validar ponta a ponta a mecânica de push (Android/FCM → Rails → `device_tokens` → scheduler → dispatcher → FCM → aparelho → clique/deep link → métricas), usando o admin de teste. Nenhum commit foi feito — todas as mudanças estão no working tree, pequenas, isoladas e reversíveis.

---

## 1. Resumo executivo

- **A mecânica de push já existia e está bem estruturada e testada.** Esta bateria **não reconstruiu** nada; validou o existente e preencheu lacunas de ferramentas/observabilidade.
- **Camadas automatizadas: APROVADO.** Backend **47 specs verdes**; frontend **33 testes verdes**; typecheck e lint limpos nos arquivos alterados.
- **Teste real no aparelho: INCONCLUSIVO (pendente).** Não foi possível executá-lo nesta sessão porque (a) `adb`/`adb.exe` não estão no PATH deste shell e (b) o banco de dev local não contém o usuário admin de produção. As ferramentas e o roteiro estão prontos (seções 6 e 10).
- **1 BLOQUEADOR encontrado (não introduzido por esta bateria):** colisão de constante `ExperimentAssignment` — um `app/models/experiment_assignment.rb` **não rastreado** (parte de uma feature de _product analytics_ em andamento na mesma árvore) sobrepõe o service `ExperimentAssignment` e **quebra o dispatcher de push** nesta árvore de trabalho. Detalhes na seção 7.

**Classificação final:** `APROVADO` (automatizado) + `INCONCLUSIVO` (aparelho físico) — condicionado à resolução do bloqueador da seção 7 antes de qualquer envio real.

---

## 2. Arquitetura encontrada (fluxo real)

```
web/src/shared/lib/pushNotifications.ts   requestPermissions→register (só granted), listeners 1x, dedup, token mascarado
  → POST /api/v1/device_tokens             upsert por token, re-attach ao user, re-enable   (device_tokens_controller.rb)
  → device_tokens                          enabled, invalidated_at, permission_status, last_seen_at, app_version…
  → cron VPS */15 → rake push_activation:run_reminders / run_recovery / dispatch_due          (push_activation.rake)
  → FirstWorkout{Reminder,Recovery}EligibilityJob → cria NotificationDelivery(scheduled)      (app/jobs/*)
  → DispatchDuePushJob → PushDispatchService  claim atômico, retry/backoff, invalida token morto
  → FirebasePushService (FCM HTTP v1 + googleauth)  200→sent / UNREGISTERED|404→invalid_token / 5xx→temporário
  → app pushNotificationActionPerformed → allowlist deep link → /workouts/ready               (push-deep-link.ts)
  → POST /notification_deliveries/:id/opened  (atribuição)
```

- **Elegibilidade** (`push_activation_eligibility.rb`): flags `ACTIVATION_PUSH_ENABLED` / `ACTIVATION_PUSH_EXPERIMENT_ENABLED`, opt-out, timezone (`PreferredWorkoutSchedule`), cooldown 20h, experimento A/B.
- **Credenciais Firebase**: só via ENV (`FIREBASE_SERVICE_ACCOUNT_JSON[_BASE64]` / `FIREBASE_PROJECT_ID`). Projeto backend detectado: **`easyhealth-analytics`**.
- **Sem worker/cron in-repo**: o envio recorrente depende de cron externo na VPS (`*/15`), **não provisionado por script de deploy** (risco pré-existente — seção 7).

---

## 3. Usuário testado

Não confirmado nesta sessão: o banco de **dev local** não contém o admin de produção, e o alvo real do aparelho é a **API de produção**. A confirmação deve ser feita **na VPS** com a task read-only criada:

```bash
docker compose -f docker-compose.prod.yml exec api bin/rails "push:test:inspect_user[mail.marcus.reis@gmail.com]"
```

- O e-mail informado na demanda (`mail.marcus.reis@gmai.com`) tem `l` faltando; a memória/config do projeto usa `mail.marcus.reis@gmail.com`. A task busca **exato + variações próximas** e **aborta se houver mais de um parecido**, sem corrigir/criar nada. O registro real deve ser confirmado por ela (não presuma).
- A saída mascara o token (`DeviceToken#masked_token`) e nunca imprime secrets.

---

## 4. Resultado por etapa

| ID | Etapa | Resultado | Evidência | Próxima ação |
|----|-------|-----------|-----------|--------------|
| 1 | App pede permissão (Android 13+) | OK (código) | `POST_NOTIFICATIONS` no manifesto; `requestPermissions` gated | Confirmar no aparelho (Cenário D) |
| 2 | FCM gera token | Não comprovado | requer aparelho | Cenário A/B |
| 3 | App envia token à API | OK (código+teste) | `syncToken` + Vitest | Confirmar `push:test:inspect_user` |
| 4 | API salva/atualiza device_token | OK (specs) | `device_tokens_spec` (upsert, re-attach, re-enable) | — |
| 5 | Backend identifica elegível | OK (specs) | `push_activation_eligibility_spec` | — |
| 6 | Job agenda notificação | OK (specs) | `first_workout_reminder_eligibility_job_spec` | — |
| 7 | Dispatcher envia ao FCM | OK (specs) — **bloqueado em runtime local** | `push_dispatch_service_spec`; ver seção 7 | Resolver colisão ExperimentAssignment |
| 8 | Firebase aceita | Não comprovado | requer envio real | `push:test:send_now` na VPS |
| 9 | Aparelho recebe | Não comprovado | requer aparelho | Cenários A/B/C |
| 10 | Clique abre rota | OK (allowlist testada) | `push-deep-link.test.ts` | Confirmar no aparelho |
| 11 | Métricas/eventos | OK (parcial) | eventos back+front; novos `push_provider_accepted/rejected` | — |
| 12 | Tokens inválidos desativados | OK (specs) | `firebase_push_service_spec` + dispatch | Cenário E no aparelho |
| 13 | Opt-out respeitado | OK (specs) | `push_activation_eligibility_spec` | Cenário G |

Status permitidos: OK · Parcial · Ausente · Quebrado · Não comprovado.

---

## 5. Testes automatizados

**Backend (RSpec)** — executados via Docker (Postgres) + bundle local (Ruby 3.2.3):

```bash
# a partir da raiz do repo:
set -a; source .env; set +a
docker compose up -d db
cd api && DB_HOST=localhost DB_PORT=5433 RAILS_ENV=test bundle exec rails db:test:prepare
DB_HOST=localhost DB_PORT=5433 RAILS_ENV=test bundle exec rspec \
  spec/services/firebase_push_service_spec.rb \
  spec/services/admin_push_test_service_spec.rb \
  spec/requests/api/v1/admin_push_test_spec.rb \
  spec/requests/api/v1/device_tokens_spec.rb \
  spec/services/push_dispatch_service_spec.rb \
  spec/services/push_activation_eligibility_spec.rb \
  spec/jobs/first_workout_reminder_eligibility_job_spec.rb
# => 47 examples, 0 failures
```

> ⚠️ Para reproduzir o verde é preciso remover temporariamente o arquivo **não rastreado** `api/app/models/experiment_assignment.rb` (seção 7). Com ele presente, 6 specs existentes falham com `undefined method 'variant_for'`.

**Frontend (Vitest):**

```bash
cd web && npx vitest run \
  src/__tests__/push-diagnostics.test.ts \
  src/__tests__/push-notifications.test.ts \
  src/__tests__/push-deep-link.test.ts \
  src/__tests__/pre-permission-card.test.tsx
# => 4 files, 33 tests passed
cd web && npx tsc --noEmit        # 0 erros
cd web && npx eslint <arquivos alterados>   # 0 erros nos arquivos desta bateria
```

Cobertura nova: interpretação de resposta FCM (200/UNREGISTERED/404/5xx/blank), corpo da mensagem (channel/priority/data stringificada), cache OAuth; endpoint admin self-only (403 não-admin, ignora `user_id` de params, 422 sem device, 429 rate-limit, auditoria, sem token na resposta); re-attach de token entre usuários; `collectPushDiagnostics` (mascara token, reflete sync), `open-settings`/local-notification/`requestApiTestPush`.

---

## 6. Testes reais (pendentes — roteiro pronto)

Não executados nesta sessão (sem `adb` no PATH; alvo = produção). Pré-condições e cenários A–H em **§10**. Para cada cenário registrar: data/hora, `correlation_id`, estado do app, FCM aceitou?, app recebeu?, clique?, rota aberta, evidência (logcat/print).

---

## 7. Problemas encontrados

### 🔴 BLOQUEADOR — colisão de constante `ExperimentAssignment`
- `api/app/services/experiment_assignment.rb` (committed, usado pelo push: `variant_for`, `should_send?`) **colide** com `api/app/models/experiment_assignment.rb` (**não rastreado**, parte de uma feature de _product analytics_ em andamento na mesma árvore — migrations `20260715120003_create_analytics_experiment_assignments` etc.).
- Em runtime, o **model vence**; `ExperimentAssignment.variant_for` fica indefinido e **`PushDispatchService#call` e `PushActivationEligibility.should_send?` quebram** (`NoMethodError`).
- **Impacto:** nesta árvore de trabalho, o envio real de push está **quebrado**. Num checkout limpo (CI/produção do commit atual) o service funciona; o risco é a feature de analytics ser mesclada **sem resolver a colisão**.
- **Ação recomendada (fora do escopo desta bateria, decisão do dono do código):** renomear um dos dois (ex.: mover o service para `ActivationExperiment` ou namespacear o model em `Analytics::ExperimentAssignment`) antes de qualquer envio real. **Não alterei nenhum dos dois arquivos.**

### 🟠 Alto — cron de push não provisionado
`push_activation:run_reminders/run_recovery/dispatch_due` dependem de cron externo na VPS (`docs/activation-push.md:57-68`); nenhum script de deploy instala isso. Sem o cron, nada é enviado no horário. (Pré-existente.)

### 🟡 Médio — consistência de projeto Firebase não verificável aqui
Backend usa projeto `easyhealth-analytics`; o `google-services.json` do Android não é versionado (injetado no CI). Confirmar que **pertencem ao mesmo projeto FCM** — senão o FCM aceita mas o aparelho registrado em outro projeto nunca recebe.

### 🟡 Médio — credencial Firebase em `.env` local
`.env` contém `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`. Confirmado **gitignored** (não vazou pelo git). Manter fora de logs/compartilhamento; considerar rotação se já foi exposto em outro canal.

### 🔵 Baixo — lint pré-existente
`web/src/app/(app)/admin/page.tsx:222` já viola `react-hooks/set-state-in-effect` (não introduzido aqui).

---

## 8. Alterações realizadas (apenas arquivos desta bateria)

**Backend — criados:** `api/app/services/admin_push_test_service.rb`, `api/app/services/push_test.rb`, `api/spec/services/firebase_push_service_spec.rb`, `api/spec/services/admin_push_test_service_spec.rb`, `api/spec/requests/api/v1/admin_push_test_spec.rb`.
**Backend — alterados:** `admin_controller.rb` (action `push_test`), `config/routes.rb` (`post :push_test`), `lib/tasks/push_test.rake` (namespace `push:test:*`), `app/jobs/activation_push_scheduler_job.rb` (param `only_user_ids:`), `app/services/push_dispatch_service.rb` (eventos provider + `correlation_id` + digest), `app/services/relationship_event_tracker.rb` (3 eventos), `spec/requests/api/v1/device_tokens_spec.rb` (re-attach).
**Frontend — criados:** `web/src/app/(app)/admin/push/push-diagnostics-section.tsx`, `web/src/__tests__/push-diagnostics.test.ts`.
**Frontend — alterados:** `web/src/shared/lib/pushNotifications.ts` (diagnostics + open-settings + local + api-test), `web/src/app/(app)/admin/page.tsx` (render do painel), `web/package.json` + `package-lock.json` (2 plugins).
**Infra/docs — criados:** `scripts/android/push_diagnostics.sh`, este relatório. **Alterado:** `.gitignore` (reports do adb).

**Dependências novas (aprovadas):** `@capacitor/local-notifications@^8.2.1`, `capacitor-native-settings@^8.1.0` — exigem novo build Android (`npx cap sync android` + AAB) para funcionarem no aparelho.

> **Não são desta bateria** (feature de _product analytics_ concorrente na mesma árvore, **não tocada**): `app/models/analytics/*`, `product_analytics_event.rb`, `app/models/experiment_assignment.rb`, migrations `20260715*`, `config/analytics/*`, refactor `web/src/shared/lib/analytics/*`, `layout.tsx`, `auth-context.tsx`, `analytics-tracker.tsx`, `schema.rb`, e specs/tests de analytics. Ao commitar, separe estes do trabalho de push.

---

## 9. Configuração necessária em produção (sem valores secretos)

- **ENV backend:** `ACTIVATION_PUSH_ENABLED=true`, `ACTIVATION_PUSH_EXPERIMENT_ENABLED` (conforme rollout), `FIREBASE_SERVICE_ACCOUNT_JSON[_BASE64]`, `FIREBASE_PROJECT_ID` (ou dentro do JSON).
- **CI Android:** secret `GOOGLE_SERVICES_JSON_BASE64` (mesmo projeto FCM do backend), `applicationId = com.EasyHealth.myapp`.
- **Cron VPS (`*/15`):** `push_activation:run_reminders`, `push_activation:run_recovery`, `push_activation:dispatch_due` — **provisionar manualmente** (não há instalador no deploy).
- **Endpoint de teste:** `POST /api/v1/admin/push_test` (admin, self-only, rate-limit 30s, auditado). Nenhuma env nova (`PUSH_TEST_MODE`/`PUSH_TEST_ALLOWED_EMAILS` **não** foram introduzidas — guarda por `admin?`).

---

## 10. Comandos operacionais (repetir a bateria)

### Inspeção e envio controlado (VPS, alvo = admin)
```bash
# read-only (identifica o usuário real, sem alterar nada):
bin/rails "push:test:inspect_user[mail.marcus.reis@gmail.com]"
bin/rails "push:test:inspect_environment"
bin/rails "push:test:report[mail.marcus.reis@gmail.com]"

# envio de teste (payload "Teste EasyHealth", só ao admin, com correlation_id):
bin/rails "push:test:send_now[mail.marcus.reis@gmail.com]"

# fila/scheduler/dispatcher reais escopados ao admin:
bin/rails "push:test:schedule[mail.marcus.reis@gmail.com,2]"
bin/rails "push:test:run_scheduler[mail.marcus.reis@gmail.com]"
bin/rails "push:test:run_dispatcher[mail.marcus.reis@gmail.com]"

# prova de invalidação em token fake isolado (não toca tokens reais):
bin/rails "push:test:invalidate_fake_token[mail.marcus.reis@gmail.com]"
```
_(Em produção: prefixe com `docker compose -f docker-compose.prod.yml exec api`.)_

### Diagnóstico no aparelho (ADB)
```bash
# expor o adb do Windows no PATH do WSL, se necessário, depois:
scripts/android/push_diagnostics.sh          # snapshot + captura filtrada 30s
scripts/android/push_diagnostics.sh 60       # captura 60s
# relatório salvo (tokens mascarados) em scripts/android/reports/ (gitignored)
```
PowerShell (equivalentes):
```powershell
adb shell dumpsys package com.EasyHealth.myapp | Select-String versionName,POST_NOTIFICATIONS
adb shell appops get com.EasyHealth.myapp POST_NOTIFICATION
adb shell dumpsys notification --noredact | Select-String workout_reminders
adb logcat -c ; adb logcat -v time FirebaseMessaging:V Capacitor:V *:S
adb shell dumpsys activity activities | Select-String com.EasyHealth.myapp
```

### Pré-condições do teste real
Usuário confirmado (§3) · app do track interno instalado e logado como admin · permissão concedida · token ativo no backend · `ACTIVATION_PUSH_ENABLED=true` · cron/worker ativos · resolver bloqueador §7.

### Cenários (registrar correlation_id + evidência em cada)
- **A — App aberto:** `send_now` → callback foreground (evento `push_received_foreground`/log Capacitor).
- **B — Background:** `send_now` → notificação no sistema → clicar → abre `/workouts/ready` → evento de clique.
- **C — Encerrado:** force-stop → `send_now` → recebe → clica → cold start + navegação pós-auth.
- **D — Permissão negada:** revogar no Android → status ao backend → scheduler não envia → CTA "abrir config" (agora intent real) → reativar → novo registro.
- **E — Token inválido:** `invalidate_fake_token` → confirma `invalidated_at` no fake; tokens reais intactos.
- **F — Erro temporário:** coberto por spec (5xx → retry, sem invalidar, sem duplicar).
- **G — Opt-out:** desativar categoria → `run_scheduler` → nenhum delivery criado → reativar → volta a enviar.
- **H — Scheduler real:** ajustar horário elegível temporariamente → `run_scheduler` → delivery pendente → `run_dispatcher` → recebe → restaurar dados.

---

## Critério de aprovação (checklist do teste real)
- [ ] permissão concedida  · [ ] token real no backend pertencente ao admin  · [ ] FCM aceitou
- [ ] aparelho recebeu em background  · [ ] clique abriu a rota certa  · [ ] evento de clique registrado
- [ ] opt-out impediu disparo  · [ ] token inválido desativado  · [ ] erro temporário com retry
- [ ] nenhum outro usuário recebeu  · [ ] nenhum secret/token completo em logs
