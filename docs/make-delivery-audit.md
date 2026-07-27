# Auditoria de entregas ao Make

## Fluxo

`user_events` continua sendo o outbox principal. Cada evento elegível gera uma
tentativa em `MakeWebhookDeliveryJob`, entregue por `MakeWebhookClient` ao
Custom Webhook do Make. O status `accepted_by_make` significa somente que o
webhook respondeu HTTP 2xx.

Estados de entrega:

- `pending`: evento gerado e aguardando envio.
- `sending`: tentativa em andamento.
- `accepted_by_make`: webhook respondeu HTTP 2xx.
- `retrying`: erro com nova tentativa agendada.
- `failed_to_reach_make`: erro/timeout sem novas tentativas.
- `dead_letter`: HTTP não 2xx sem novas tentativas.
- `disabled`: evento gerado, mas gate/configuração bloqueou envio.
- `skipped`: evento conhecido, mas sem comunicação habilitada.

O processamento interno do Make fica em `make_processing_status`. Sem callback,
o valor permanece `unknown`.

## Callback no Make

Endpoint:

```text
POST /api/v1/integrations/make/event_delivery_callbacks
Authorization: Bearer <MAKE_DELIVERY_CALLBACK_TOKEN>
```

Payload:

```json
{
  "event_id": "1120",
  "idempotency_key": "workout_created_not_started-1120",
  "event_name": "workout_created_not_started",
  "status": "routed",
  "scenario": "workout-created-not-started-email",
  "execution_id": "make-execution-id",
  "occurred_at": "2026-07-26T18:30:00Z",
  "message": "Evento encaminhado para o fluxo de e-mail"
}
```

Status aceitos: `received`, `routed`, `filtered`, `completed`, `failed`.

Adicionar um módulo HTTP no fim das rotas do cenário:

- Rota executada com sucesso: `completed`.
- Evento barrado conscientemente: `filtered`.
- Erro tratado dentro do cenário: `failed`.

## Deploy

```bash
docker compose -f docker-compose.prod.yml exec api bin/rails db:migrate
```

```bash
docker compose -f docker-compose.prod.yml exec web npm run build
```

## Validação em produção

```bash
docker compose -f docker-compose.prod.yml exec api bin/rails make_webhook:audit
```

Use `EXPECT_DATA=1` quando a base deveria ter dados. A task é somente leitura e
retorna JSON com `ok: false` para base vazia, sem `abort`/`SystemExit`.

```bash
docker compose -f docker-compose.prod.yml exec api env EXPECT_DATA=1 HOURS=24 LIMIT=20 bin/rails make_webhook:audit
```

Evento controlado usando o pipeline real:

```bash
docker compose -f docker-compose.prod.yml exec api bin/rails "communication_events:deliver[first_workout_completed,EMAIL_DO_USUARIO]"
```
