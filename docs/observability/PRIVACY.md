# Privacidade em Observabilidade — EasyHealth

Complementa [docs/analytics/PRIVACY_AND_DATA_HANDLING.md](../analytics/PRIVACY_AND_DATA_HANDLING.md) e [docs/mobile-analytics-privacy.md](../mobile-analytics-privacy.md).

## Regra

**Nunca** entram em log, evento de observabilidade, incidente, alerta ou payload do painel:

- dados de saúde de qualquer tipo
- e-mail, nome, telefone, endereço, data de nascimento, CPF
- senha, token (Google, FCM, sessão), cookie, header `Authorization`
- payload bruto do Google, do FCM ou do Stripe
- corpo de requisição
- mensagem livre de exceção (só a **classe**)

## Como isso é garantido

### Identificadores externos são hasheados

`Observability::Context` nunca expõe `installation_id` ou `session_id` crus para fora do processo:

```
installation_id "abc-123"  →  installation_ref "ins_9f2c4a1b8e3d7f60"
session_id      "xyz-789"  →  session_ref      "ses_1a4b2c3d5e6f7080"
user_id         42         →  user_ref         "u_42"
```

HMAC-SHA256 com `OBSERVABILITY_HASH_SALT` (ou `secret_key_base`), truncado em 16 caracteres. Estável, para correlacionar o mesmo aparelho entre linhas; irreversível, para não vazar o identificador.

`user_ref` é a chave primária interna — não é dado pessoal e não serve para nada fora do nosso banco. O valor cru de `installation_id` continua persistido em `app_installations` (já era), mas nunca sai em log.

### Sanitização em duas camadas

`Observability::Logger#safe_metadata`:

1. `RelationshipEventTracker.sanitize_metadata` — remove `password`, `token`, `secret`, `authorization`, `card`, `stripe`, `cpf`, `ssn`, `cvv`, `api_key`…
2. `Observability::Logger::PERSONAL_KEY_PATTERN` — remove `email`, `name`, `phone`, `address`, `birth`, `document`, `avatar`, `photo`…
3. Corte em 2 KB serializados e profundidade 3.

**Por que duas camadas:** o sanitizador compartilhado mantém `email` e `name` de propósito — o pipeline do Make existe para enviar mensagens a pessoas e precisa deles. Log não precisa e vai para um destino diferente. Endurecer o sanitizador compartilhado quebraria os payloads do Make.

A segunda camada tem uma allow-list de chaves técnicas (`event_name`, `job_name`, `table_name`…) para que o padrão `name` não engula identificadores de código.

### Vocabulários fechados

`Observability::Events` coage cada dimensão a uma lista fechada:

- `auth_flow` ∈ `native`, `web`, `web_mobile`, `unknown`
- `auth_intent` ∈ `login`, `sign_up`, `unknown`
- `error_code` ∈ `invalid_token`, `invalid_audience`, `consent_required`, `account_deleted`, `provider_error`, `internal_error`
- `link_result` ∈ `linked`, `already_linked`, `conflict`, `not_found`, `error`

Um valor fora da lista vira `internal_error` / `unknown`. Uma mensagem de exceção não consegue virar dimensão nova.

### Códigos de erro em heartbeats

`Observability::Heartbeat` grava a **classe** da exceção, nunca a mensagem:

```ruby
Observability::Heartbeat.failed!("push_dispatch", error_code: e.class.name)  # "ArgumentError"
```

O valor é normalizado (`[^A-Za-z0-9_.:-]` → `_`, máx. 64 caracteres), porque é renderizado no painel admin.

### Fingerprint sem identificadores

`Observability::Fingerprint::ALLOWED_DIMENSIONS` restringe as dimensões de um incidente a chaves de baixa cardinalidade (`build_group`, `auth_flow`, `heartbeat_key`, `integration`, `job`, `platform`, `route`).

Duas razões: um ref de usuário criaria **um incidente por usuário afetado**, e a dimensão acabaria no payload enviado ao webhook de alerta.

### Timeline de investigação

`GET /api/v1/admin/observability/timeline` devolve nome do evento, horário e uma **allow-list** de campos enum (`result`, `error_code`, `auth_flow`, `link_result`), cada um truncado em 64 caracteres.

O blob `properties` **nunca** é ecoado inteiro — ele pode conter chaves arbitrárias vindas do cliente. Há spec verificando que e-mail e nome não aparecem na resposta mesmo quando um evento os carrega.

### Alertas

O payload do `Observability::Notifier` leva id do incidente, título, severidade, check, valores, amostra, dimensões permitidas e URL do painel. Não leva usuário, e-mail nem installation id. Nunca há alerta por usuário individual.

`OBSERVABILITY_ALERT_WEBHOOK_URL` e `_TOKEN` são deliberadamente omitidos do bloco `thresholds` do painel — há spec para isso.

## Controle de acesso

- Toda ação do controller admin tem `require_admin!` **no servidor**. O gate do frontend é só um redirect de conveniência.
- Reconhecer/resolver grava `admin:<id>` em `acknowledged_by` / `resolved_by`.
- Segredos só em ENV. Nenhum valor real neste repositório.
- O env file da réplica BI (`/etc/easyhealth/bi_replica.env`) fica fora do repositório, com `chmod 600`.

## Retenção

| Dado | Retenção |
|---|---|
| `observability_check_results` | 90 dias (`OBSERVABILITY_CHECK_RETENTION_DAYS`), podado por `rake observability:resolve_stale` |
| `observability_incidents` | sem poda automática (volume baixo; histórico é útil) |
| `observability_heartbeats` | uma linha por processo, sobrescrita |
| Logs JSON | driver `json-file` do Docker; retenção definida pelo daemon |

## Testes que travam regressão

| Spec | Garante |
|---|---|
| `spec/services/observability/logger_spec.rb` | e-mail e token não sobrevivem em `metadata`; `installation_id` cru nunca aparece |
| `spec/services/observability/context_spec.rb` | refs são hasheados, estáveis e distintos |
| `spec/services/observability/heartbeat_spec.rb` | `last_error_code` não carrega mensagem |
| `spec/requests/observability_request_context_spec.rb` | log de requisição não contém identificadores crus |
| `spec/requests/api/v1/admin/observability_spec.rb` | timeline sem e-mail/nome; `thresholds` sem segredos |
| `src/__tests__/admin-observability.test.tsx` | nenhum e-mail renderizado no DOM |
