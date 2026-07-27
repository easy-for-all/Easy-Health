# Matriz de Alertas — EasyHealth

Todos os checks rodam a cada 15 min via `rake observability:check`. Thresholds configuráveis por ENV, lidos em `Observability::Config` e exibidos no painel (bloco `thresholds`).

**Regra geral:** amostra abaixo do piso → `insufficient_data`, sem valor, sem incidente. Nunca zero.

---

## Prioridade 1 — Cadastro Android por build

### `android_registration_conversion`

| | |
|---|---|
| **Fonte** | `app_installations` (Android), agrupado por coorte de build |
| **Definição** | instalações com `user_id` ÷ instalações criadas na janela |
| **Janela** | 24h, comparada com linha de base dos 7 dias anteriores |
| **Amostra mínima** | 10 instalações **por coorte** (`OBSERVABILITY_MIN_ANDROID_SAMPLE`) |
| **Warning** | conversão < 30% **ou** queda > 40% contra a base |
| **Critical** | conversão < 15% **ou** queda > 60% contra a base |
| **ENV** | `ANDROID_REGISTRATION_WARNING_RATE`, `ANDROID_REGISTRATION_CRITICAL_RATE`, `ANDROID_REGISTRATION_WARNING_DROP`, `ANDROID_REGISTRATION_CRITICAL_DROP` |
| **Ação** | [RUNBOOK 1](RUNBOOK.md#1-cadastro-android-caiu) |
| **Responsável** | quem publicou o build mais recente |

Por que o denominador é `app_installations` e não eventos: eventos são condicionados a consentimento e subcontariam exatamente os usuários que queremos encontrar.

---

## Prioridade 2 — Vínculo de instalação

### `android_installation_link_rate`

| | |
|---|---|
| **Fonte** | `app_installations`, coortes `tracking`/`current` (legado excluído) |
| **Definição** | instalações vinculadas ÷ instalações da coorte, 24h |
| **Amostra mínima** | 10 por coorte |
| **Warning** | < 50% (`ANDROID_LINK_WARNING_RATE`) |
| **Critical** | < 30% (`ANDROID_LINK_CRITICAL_RATE`) |
| **Ação** | [RUNBOOK 2](RUNBOOK.md#2-instalacoes-nao-estao-vinculando) |

### `authenticated_without_installation_link`

| | |
|---|---|
| **Fonte** | `app_installations` com `last_authenticated_at` preenchido e `user_id` nulo |
| **Amostra mínima** | **nenhuma** — ver abaixo |
| **Critical** | qualquer linha com mais de 5 min (`OBSERVABILITY_LINK_TOLERANCE_SECONDS`) |
| **Ação** | [RUNBOOK 2](RUNBOOK.md#2-instalacoes-nao-estao-vinculando) |

Este é determinístico, não estatístico. `AppInstallationReconciliation` grava `user_id` e `last_authenticated_at` no **mesmo** `update_columns` — a linha é logicamente impossível. Não pode ser explicada por tráfego baixo ou amostra azarada, então uma única ocorrência já abre incidente.

---

## Prioridade 3 — Login Google

### `google_auth_error_rate`

| | |
|---|---|
| **Fonte** | `product_analytics_events` (`google_auth_succeeded` / `google_auth_failed`) |
| **Definição** | falhas ÷ tentativas, **separado por fluxo** (`native`, `web`, `web_mobile`) |
| **Janela** | 30 min (`GOOGLE_AUTH_WINDOW_MINUTES`) |
| **Amostra mínima** | 10 tentativas por fluxo (`OBSERVABILITY_MIN_GOOGLE_AUTH_SAMPLE`) |
| **Warning** | > 10% (`GOOGLE_AUTH_WARNING_ERROR_RATE`) |
| **Critical** | > 25% (`GOOGLE_AUTH_CRITICAL_ERROR_RATE`) |
| **Ação** | [RUNBOOK 3](RUNBOOK.md#3-google-native-comecou-a-falhar) / [RUNBOOK 4](RUNBOOK.md#4-oauth-web-comecou-a-falhar) |

A separação por fluxo é o ponto: uma queda total do native some numa taxa agregada com tráfego web saudável. O `error_code` predominante vai na dimensão `top_error_code`.

Códigos possíveis: `invalid_token`, `invalid_audience`, `consent_required`, `account_deleted`, `provider_error`, `internal_error`.

### `google_auth_consent_anomaly`

| | |
|---|---|
| **Definição** | `consent_required` em tentativa com `auth_intent=sign_up` **e** `terms_accepted=true` |
| **Amostra mínima** | nenhuma |
| **Critical** | qualquer ocorrência |
| **Ação** | [RUNBOOK 3](RUNBOOK.md#3-google-native-comecou-a-falhar) |

`consent_required` **esperado**: login numa conta que ainda não existe. O cliente não coletou consentimento, o servidor recusa, e a UI manda para o cadastro. Correto.

`consent_required` **anômalo**: o cliente já coletou os termos e mesmo assim foi recusado. Isso é bug. Só o segundo caso alerta; o primeiro aparece como contagem em `dimensions.expected_consent_required`.

---

## Prioridade 4 — Jobs e integrações silenciosas

### `stale_heartbeat:<key>`

| | |
|---|---|
| **Fonte** | `observability_heartbeats` |
| **Warning** | sem sucesso por > 1,5× o intervalo esperado |
| **Critical** | > 2× o intervalo |
| **Caso especial** | registrado e nunca bem-sucedido, ainda dentro do primeiro intervalo → `insufficient_data` |

O caso especial evita que todo deploy acenda o painel inteiro com processos que simplesmente ainda não tiveram sua primeira execução agendada.

Processos monitorados: `relationship_daily_job` (24h), `make_pending_retry` (1h), `make_webhook_delivery` (24h), `stripe_webhook_processing` (24h), `android_analytics_ingestion` (6h), `push_dispatch` (1h), `observability_health_check` (15min), `bi_replica_refresh` (24h).

### `repeated_job_failure`

Warning com 3 falhas consecutivas, critical com 5 (`OBSERVABILITY_JOB_FAILURE_WARNING_STREAK` / `_CRITICAL_STREAK`).

### `make_delivery_backlog`

| | |
|---|---|
| **Fonte** | `user_events` com `make_delivery_status='pending'` |
| **Piso de idade** | 30 min (`OBSERVABILITY_MAKE_BACKLOG_AGE_MINUTES`) |
| **Warning** | > 10 pendentes |
| **Critical** | > 50 pendentes |
| **Ação** | `rake make_webhook:retry_pending` — [RUNBOOK 5](RUNBOOK.md#5-make-parou) |

Fila vazia é saudável, não é falha. O piso de idade existe porque o adapter `:async` legitimamente descarta retries em cada deploy — sem ele o check dispararia a cada release.

### `stripe_webhook_failure`

`stripe_events` com `status <> 'processed'` na última hora. Warning ≥ 1, critical ≥ 5. [RUNBOOK 6](RUNBOOK.md#6-stripe-webhook-parou).

Assinatura inválida **não** conta: um POST não assinado é um chamador rejeitado, não um pipeline quebrado — contá-lo deixaria qualquer um na internet abrir incidente.

### `replica_refresh_stale`

| | |
|---|---|
| **Fonte** | heartbeat `bi_replica_refresh` |
| **Avaliado apenas após** | `BI_REPLICA_EXPECTED_HOUR` (padrão 3) + `BI_REPLICA_GRACE_MINUTES` (padrão 90), no fuso de produção |
| **Critical** | sem sucesso desde a meia-noite local |
| **Ação** | [RUNBOOK 7](RUNBOOK.md#7-replica-nao-atualizou) |

**O horário real do cron não é conhecível pelo repositório.** `scripts/bi_replica/install_cron.sh` só fornece um padrão (`0 2 * * *`) via `CRON_SCHEDULE`; o que está instalado na VPS é estado operacional. Confira com `crontab -l` e mantenha `BI_REPLICA_EXPECTED_HOUR` coerente.

### `android_analytics_ingestion_stale`

| | |
|---|---|
| **Fonte** | `product_analytics_events` por `occurred_at` (não `received_at`, que não tem índice) |
| **Janela** | 2h (`OBSERVABILITY_ANALYTICS_WINDOW_HOURS`) |
| **Piso de tráfego** | mediana de 7 dias < 5 eventos/hora → `insufficient_data` |
| **Critical** | zero eventos **e** instalações ativas no período |
| **Warning** | zero eventos e nenhuma instalação ativa |
| **Ação** | [RUNBOOK 8](RUNBOOK.md#8-nenhum-evento-android-chegou) |

Ausência de eventos só significa algo se houve tráfego para produzi-los. Uma madrugada quieta não pode virar incidente.

---

## API e infraestrutura

### `api_error_rate` / `api_latency_p95`

| | |
|---|---|
| **Fonte** | `Observability::HttpStats` — **em memória, no processo Puma** |
| **Janela** | 15 min, zera a cada deploy |
| **Amostra mínima** | 20 requisições (`OBSERVABILITY_MIN_HTTP_SAMPLE`) |
| **Warning** | 5xx > 5% · p95 > 2s |
| **Critical** | 5xx > 15% · p95 > 5s |
| **Ação** | [RUNBOOK 9](RUNBOOK.md#9-api-ficou-lenta) |

Escopo limitado e declarado. Não há CPU, memória, disco nem restart de container nesta entrega — ver [ARCHITECTURE.md](ARCHITECTURE.md#o-que-ainda-nao-existe).

---

## Notificações

| | |
|---|---|
| **Flag** | `OBSERVABILITY_ALERTS_ENABLED` (padrão **false**) |
| **Destino** | `OBSERVABILITY_ALERT_WEBHOOK_URL` + `OBSERVABILITY_ALERT_WEBHOOK_TOKEN` |
| **Cooldown** | 60 min (`OBSERVABILITY_ALERT_COOLDOWN_MINUTES`) |
| **Ignora cooldown** | escalada para critical e resolução |

Eventos: `observability_incident_opened`, `observability_incident_escalated`, `observability_incident_resolved`.

Nunca há alerta por usuário individual. O payload leva id do incidente, check, valores, dimensões permitidas e link do painel — sem PII. Ver [PRIVACY.md](PRIVACY.md).
