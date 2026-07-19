# Contrato — Make chamando o dispatch de push da EasyHealth

Como configurar o cenário do Make para, ao receber um evento, solicitar um push.
O Make orquestra (se/quando/template); a EasyHealth valida e envia. O Make pede por
`user_id`, **nunca** por token.

Ver também: `docs/make-push-webhook.md` (a perna evento → Make).

## Endpoint

```http
POST https://easyhealth.art/api/v1/integrations/make/push_dispatches
Authorization: Bearer {{MAKE_PUSH_DISPATCH_TOKEN}}
Content-Type: application/json
```

- Bearer dedicado (separado do `MAKE_WEBHOOK_SECRET`), comparado em tempo constante.
  Rotação sem downtime: `MAKE_PUSH_DISPATCH_TOKEN_CURRENT` + `_PREVIOUS` (ambos aceitos).
- HTTPS obrigatório em produção. Body máximo 8 KB.

## Body

```json
{
  "event_id": "1120",
  "user_id": 9,
  "notification_type": "workout_reminder",
  "campaign_key": "workout_not_started_v1",
  "title": "Seu treino está esperando por você 💪",
  "body": "Que tal começar agora?",
  "route": "/workouts/ready",
  "data": { "workout_id": "999", "source": "make" }
}
```

Campos aceitos (allowlist): `event_id`, `user_id`, `notification_type`, `campaign_key`,
`title`, `body`, `route`, `correlation_id`, `data` (objeto de strings).

Validações (violar → `422 invalid_payload` com `detail`):
- `notification_type` ∈ `workout_reminder`, `activation_reminder`, `progress_update`,
  `account_security`, `transactional`.
- `route` começa com `/workouts`, `/workout` ou `/plan` (caminho interno seguro).
  É exposto ao app como `target_path` (campo que o deep link abre).
- `title` ≤ 120, `body` ≤ 240; sem HTML nem `javascript:`.
- `token`/`device_token`/`fcm_token`/`tokens` (topo ou dentro de `data`) → `forbidden_token_field`.

## Idempotência

Chave = `event_id + campaign_key + user_id + notification_type` (derivada do corpo;
**não** há header `Idempotency-Key`). Repetir a mesma combinação → `duplicate`, sem reenviar.

## Respostas

### Enviado (200)
```json
{
  "status": "provider_accepted",      // ou "partially_accepted"
  "dispatch_id": 42,
  "correlation_id": "make-1120",
  "tokens_attempted": 1,
  "tokens_accepted": 1,
  "tokens_rejected": 0,
  "sent": true
}
```

### Ignorado (200) — decisão de consentimento é da EasyHealth
```json
{
  "status": "skipped",
  "sent": false,
  "skip_reason": "category_opt_out",
  "dispatch_id": 123,
  "notification_type": "workout_reminder",
  "campaign_key": "user-inactive-3-days-v1",
  "correlation_id": "make-evt_ab12"
}
```
`skip_reason` ∈ `orchestration_disabled`, `user_not_found`, `global_opt_out`,
`category_opt_out`, `no_active_token`, `permission_denied`, `cooldown_active`,
`frequency_capped`, `rate_limited`, `invalid_payload`, `duplicate`.
`user_not_found` volta como skip neutro (200) de propósito, para não permitir
enumeração de usuários. `dispatch_id` só aparece quando a linha chegou a ser
criada (skips anteriores à persistência não têm id).

> `reason` continua sendo devolvido como **alias depreciado** de `skip_reason`,
> para não quebrar cenários já publicados. Consumidores novos devem ler
> `skip_reason`.

### Duplicado (200)
```json
{ "status": "duplicate", "sent": false, "skip_reason": "duplicate", "dispatch_id": 42 }
```

### Erros
| HTTP | Situação | Make deve |
| --- | --- | --- |
| 401 | Bearer ausente/errado | **não** repetir (corrigir token) |
| 422 | payload inválido (`detail`) | **não** repetir (corrigir corpo) |
| 413 | body > 8 KB | **não** repetir |
| 429 | `rate_limited` | repetir com backoff |
| 502 | `failed` (falha transitória no provedor) | **repetir** (re-despacha a mesma linha) |
| 200 | qualquer status acima | não repetir |

> `provider_accepted` = o **FCM aceitou**, NÃO é prova de entrega no aparelho. A entrega
> real só é confirmada por evento app-side (`push_opened`/received).

## Estrutura do cenário no Make

```
Custom Webhook (evento da EasyHealth, assinatura HMAC validada)
 → Router por event_name (ex.: workout_created_not_started)
 → [opcional] Delay / agendamento no timezone de {{user.timezone}}
 → montar template (title/body/route/campaign_key)
 → HTTP POST /integrations/make/push_dispatches (Bearer)
 → Error Handler: retry em 502/429; ignorar em 401/422
 → registrar resultado (dispatch_id, status)
```

Para agendamento (ex.: lembrar X horas depois):
```
Webhook → Make Data Store (pending_push, due_at no timezone do user)
 → cenário agendado a cada 15 min → buscar vencidos → HTTP dispatch → marcar processado
```

## Pré-requisitos no backend (VPS) para o envio real acontecer

```env
MAKE_PUSH_ORCHESTRATION_ENABLED=true
MAKE_PUSH_DISPATCH_TOKEN=<mesmo valor do Bearer no Make>   # openssl rand -hex 32
```
E o usuário precisa ter: token ativo, `push_enabled` + categoria habilitada,
`permission_status=granted`. Com a flag OFF o endpoint responde
`skipped/orchestration_disabled` sem enviar.

## Smoke test (curl, contra produção após deploy)

```bash
curl -sS -X POST https://easyhealth.art/api/v1/integrations/make/push_dispatches \
  -H "Authorization: Bearer $MAKE_PUSH_DISPATCH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"event_id":"smoke1","user_id":9,"notification_type":"workout_reminder",
       "campaign_key":"smoke","title":"Teste","body":"Push de teste",
       "route":"/workouts/ready","data":{"source":"make"}}'
```
Esperado (admin com aparelho registrado): `{"status":"provider_accepted","sent":true,...}`.
```
