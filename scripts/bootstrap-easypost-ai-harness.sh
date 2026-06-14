#!/usr/bin/env bash
set -euo pipefail

FORCE=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Bootstrap the EasyPost 2.0 AI harness in the current repository.

Usage:
  ./scripts/bootstrap-easypost-ai-harness.sh [--force] [--dry-run]

Options:
  --force    overwrite existing harness files
  --dry-run  show files that would be written
  --help     show this help

Run this from the root of the EasyPost 2.0 repository.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

write_file() {
  local path="$1"
  local dir
  dir="$(dirname "$path")"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would write $path"
    cat >/dev/null
    return
  fi

  mkdir -p "$dir"

  if [ -e "$path" ] && [ "$FORCE" -ne 1 ]; then
    echo "skip existing $path (use --force to overwrite)"
    cat >/dev/null
    return
  fi

  cat >"$path"
  echo "wrote $path"
}

write_file "AGENTS.md" <<'EOF'
# AGENTS.md - EasyPost 2.0

## Projeto
EasyPost 2.0 e um SaaS de automacao de postagens em redes sociais com IA para micro e pequenos empreendedores.

## Stack
- Backend: Ruby on Rails 7 API-only
- Jobs: Sidekiq + Redis
- Database: PostgreSQL
- Mobile: React Native + Expo
- Storage: AWS S3 privado ou mock local
- Auth: JWT stateless
- Billing: Stripe no MVP
- Deploy: VPS com Docker Compose

## Estrutura
- `/api`: Rails API-only
- `/mobile`: React Native + Expo
- `/modules`: agentes, skills, rules e contexto por modulo quando necessario
- `/docs`: documentacao tecnica
- `MEMORY.md`: decisoes persistentes do projeto

## Como trabalhar
- Antes de implementar mudancas medias ou grandes, leia `MEMORY.md`.
- Sempre planeje antes de implementar mudancas medias ou grandes.
- Antes de codar, liste arquivos impactados e abordagem.
- Nao implemente features grandes de uma vez.
- Trabalhe em pequenas etapas entregaveis.
- Depois de implementar, rode lint/build/test quando possivel.
- Nao recrie services, agents, skills ou padroes sem procurar os existentes.

## Regras principais
- Mobile-first.
- Codigo simples e legivel.
- Evitar overengineering.
- Regras de negocio ficam no backend Rails.
- Mobile deve cuidar de UX, estado local e chamada de API, nao de regras de negocio.
- JWT e o padrao de auth do MVP, mas sem criptografia customizada.
- Nunca commitar `.env`, secrets, tokens ou chaves.
- Stripe deve usar webhooks idempotentes e chaves restritas quando possivel.

## MVP
Priorizar:
- cadastro e login
- empresa ou pessoa
- brand profile / perfil
- criacao de posts
- geracao por IA
- agendamento de posts
- aprovacao e publicacao de posts
- historico e status dos posts
- billing/assinatura com Stripe

## QA
Toda mudanca relevante deve considerar:
- teste unitario
- teste de integracao/API quando aplicavel
- regressao dos fluxos principais:
  - cadastro
  - login
  - empresa/pessoa
  - brand profile/perfil
  - criacao de post
  - geracao por IA
  - agendamento
  - aprovacao/publicacao
  - historico/status
  - assinatura/billing
EOF

write_file "CLAUDE.md" <<'EOF'
Read `AGENTS.md`, `MEMORY.md`, and `.claude/CLAUDE.md` before making non-trivial changes.
EOF

write_file "MEMORY.md" <<'EOF'
# MEMORY.md - EasyPost 2.0

Este arquivo guarda decisoes persistentes para evitar perda de contexto entre sessoes.

## Como usar
- Leia este arquivo antes de qualquer mudanca media ou grande.
- Atualize quando uma decisao arquitetural, produto, padrao de codigo ou integracao for definida.
- Nao use para secrets, tokens, senhas, dados pessoais reais ou valores de `.env`.
- Prefira registrar decisoes curtas, datadas e acionaveis.
- Se uma decisao mudar, mantenha o historico e registre a substituicao.

## Decisoes atuais
- O backend Rails API-only e dono das regras de negocio.
- O mobile Expo consome a API e nao duplica regras de negocio.
- Auth do MVP usa JWT stateless.
- Jobs assincronos usam Sidekiq + Redis.
- PostgreSQL e a fonte de verdade.
- Storage usa S3 privado em producao e pode usar mock/local no desenvolvimento.
- Stripe entra no MVP para assinaturas/billing.
- IA deve ser encapsulada atras de services/adapters no backend.
- Fluxos de redes sociais devem registrar status, erros e tentativas.

## Padroes de arquitetura
- Controllers Rails devem ser finos.
- Services concentram casos de uso e integracoes externas.
- Models validam consistencia e relacionamentos, evitando callbacks complexos.
- Workers Sidekiq executam tarefas demoradas, retries e publicacoes agendadas.
- Mobile organiza telas e componentes por feature.
- API deve retornar JSON com status HTTP corretos e erros padronizados.

## Evitar duplicidade
Antes de criar algo novo, procurar por:
- services Rails existentes
- workers existentes
- serializers/presenters existentes
- clients/adapters de IA, Stripe ou redes sociais
- hooks/stores/components mobile existentes
- agents/skills/rules em `.agents`, `.claude` e `modules`

## Integracoes
- Stripe: usar Checkout/Billing para assinaturas, webhooks idempotentes e restricted API keys quando possivel.
- IA: `AI_PROVIDER=mock` ou `openai`; manter fallback/mock para desenvolvimento e testes.
- Redes sociais: isolar providers em adapters e persistir logs/status de publicacao.

## Decisoes pendentes
- Modelo exato de planos/precos no Stripe.
- Estrategia de refresh/expiracao dos JWTs.
- Quais redes sociais entram primeiro no MVP.
- Se aprovacao/publicacao sera manual, automatica ou hibrida no primeiro release.

## Log de decisoes
- 2026-06-14: Harness inicial definido para Rails API-only + Expo + JWT + Sidekiq + Stripe + IA.
EOF

write_file ".claude/CLAUDE.md" <<'EOF'
# PROJECT: EasyPost 2.0

## Purpose
SaaS de automacao de postagens em redes sociais com IA para micro e pequenos empreendedores.

## Required context
Before medium or large changes:
1. Read `AGENTS.md`.
2. Read `MEMORY.md`.
3. Consult relevant files in `.claude/rules`.
4. Use `.claude/skills/qa.md` for QA planning.
5. Use `.agents/skills/stripe-best-practices` for Stripe work.

## Tech stack
- Backend: Ruby on Rails 7 API-only
- Database: PostgreSQL
- Jobs: Sidekiq + Redis
- Mobile: React Native + Expo
- Storage: S3 private or local mock
- Auth: JWT stateless
- Billing: Stripe
- Deploy: Docker Compose on VPS

## Architecture
- API-first modular monolith.
- Business logic stays in Rails.
- Mobile is organized by feature and consumes the API.
- External integrations use adapters/services.
- Long-running work belongs in Sidekiq workers.

## Operating rules
- Understand the problem.
- Restate the goal simply.
- For medium/large work, list impacted files and approach before coding.
- Implement in small steps.
- Run tests/lint/build when possible.
- Update `MEMORY.md` when a durable decision is made.

## Output
- Prefer ready-to-run code.
- Keep explanations short.
- Call out tests run and tests not run.
EOF

write_file ".claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Read(./**)",
      "Edit(./**)",
      "Write(./**)",
      "Bash(ls *)",
      "Bash(find *)",
      "Bash(rg *)",
      "Bash(sed *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(bundle exec rails *)",
      "Bash(bundle exec rspec *)",
      "Bash(bundle exec rubocop *)",
      "Bash(npm install *)",
      "Bash(npm test *)",
      "Bash(npm run lint *)",
      "Bash(npx expo *)",
      "Bash(docker compose *)"
    ],
    "deny": [
      "Read(.env)",
      "Read(api/.env)",
      "Read(mobile/.env)",
      "Read(.projects/**)"
    ]
  }
}
EOF

write_file ".claude/rules/backend.md" <<'EOF'
# Backend Rules - EasyPost 2.0

## Stack
- Ruby on Rails 7 API-only
- PostgreSQL
- Sidekiq + Redis

## Architecture
- Modular monolith.
- Controllers stay thin.
- Business logic lives in services/use cases.
- External APIs live behind clients/adapters.
- Workers handle slow or retryable work.
- Avoid complex callbacks in models.

## API
- Use REST where it fits.
- Return JSON.
- Use correct HTTP status codes.
- Standardize errors.
- Validate all inputs on the backend.
- Never trust data from the mobile app.

## Jobs
- Use Sidekiq for AI generation, scheduled publishing, retries and webhook follow-ups.
- Jobs must be idempotent when possible.
- Persist status transitions for user-visible workflows.

## Data
- Use clear migrations.
- Prefer explicit fields over generic JSON blobs, except provider payloads/logs.
- Keep enough history for post status, publication attempts and billing events.
EOF

write_file ".claude/rules/mobile.md" <<'EOF'
# Mobile Rules - EasyPost 2.0

## Stack
- React Native
- Expo
- TypeScript when available

## Organization
- Organize by feature.
- Shared UI components live in a shared/common area.
- API clients should be centralized.
- Auth token handling should be isolated.

## UX
- Mobile-first.
- Fast flows for creating and approving posts.
- Clear loading, empty, error and success states.
- Avoid dense screens.
- Use platform-appropriate controls.

## Rules
- Do not put business rules in the mobile app.
- Client-side validation is only a UX helper; backend validation is authoritative.
- Store tokens with secure platform storage, not plain async storage when avoidable.
- Never log JWTs, secrets or sensitive user/business data.
EOF

write_file ".claude/rules/security.md" <<'EOF'
# Security Rules - EasyPost 2.0

## Auth
- JWT stateless is the MVP auth model.
- Do not implement custom cryptography.
- Use a maintained JWT library.
- Keep token expiry and refresh strategy explicit in `MEMORY.md`.
- Protect all authenticated endpoints.

## Secrets
- Never commit `.env`, tokens, private keys or credentials.
- Never expose secrets in logs, screenshots, issues or docs.
- Prefer restricted API keys for Stripe when possible.
- Production secrets belong in the deployment environment, not the repo.

## Personal and business data
- Ask before working with real personal data.
- Avoid exposing unnecessary personal/business data in API responses.
- Mask or omit sensitive fields in logs.

## Uploads and storage
- Validate file type and size on the backend.
- Use private S3 objects in production.
- Never trust MIME type sent by the client.

## Webhooks
- Verify webhook signatures.
- Store external event ids for idempotency.
- Handle duplicate and out-of-order events.
EOF

write_file ".claude/rules/product.md" <<'EOF'
# Product Rules - EasyPost 2.0

## Principles
- Simplicity before completeness.
- Help the user create, approve, schedule and publish posts with less effort.
- Keep flows useful for micro and small entrepreneurs.
- Avoid unnecessary screens, fields and setup steps.

## MVP
Prioritize:
- cadastro e login
- empresa ou pessoa
- brand profile / perfil
- criacao de posts
- geracao por IA
- agendamento de posts
- aprovacao e publicacao de posts
- historico e status dos posts
- billing/assinatura

## Decision rule
If a feature does not help users create, approve, schedule, publish or understand posts, it probably does not belong in the MVP.
EOF

write_file ".claude/rules/data.md" <<'EOF'
# Data Rules - EasyPost 2.0

## Database
- PostgreSQL.
- Versioned migrations.
- Clear indexes for lookups and status queues.
- Avoid excessive normalization in the MVP.

## Initial domains
- users
- companies or people
- brand_profiles
- post_requests
- generated_posts
- post_approvals
- post_schedules
- publication_attempts
- subscriptions
- billing_events

## Principles
- Keep data easy to query.
- Preserve history for status transitions.
- Never delete important user or billing data without a clear retention decision.
- Store provider payloads carefully and avoid secrets in raw JSON.
EOF

write_file ".claude/rules/testing.md" <<'EOF'
# Testing Rules - EasyPost 2.0

## Required
- New features need tests.
- Bug fixes need tests covering the bug.
- Do not change tests only to make them pass; fix the root cause.
- Do not call work complete without running relevant tests when possible.

## Backend
- Unit tests for models/services.
- Request specs for API endpoints.
- Worker specs for Sidekiq behavior.
- Webhook specs for Stripe and social providers.
- Test validations, permissions and HTTP responses.

## Mobile
- Test critical components and flows when the project test setup exists.
- Cover loading, empty, error and success states for important screens.

## Regression minimum
Before finishing relevant work, consider:
- cadastro
- login
- empresa/pessoa
- brand profile/perfil
- criacao de post
- geracao por IA
- agendamento
- aprovacao/publicacao
- historico/status
- billing/assinatura
EOF

write_file ".claude/rules/stripe.md" <<'EOF'
# Stripe Rules - EasyPost 2.0

## Use cases
- Billing/subscriptions are part of the MVP.
- Prefer Stripe Checkout + Billing for subscription signup and plan changes unless product needs require a custom flow.

## Security
- Prefer restricted API keys when possible.
- Never expose secret keys to mobile.
- Verify webhook signatures.
- Store Stripe object ids, not full sensitive payloads.

## Reliability
- Webhook handlers must be idempotent.
- Store processed event ids.
- Handle duplicate, delayed and out-of-order events.
- Keep subscription state in sync from webhooks, not only from synchronous checkout redirects.

## API version
- Verify the current Stripe API version in official Stripe docs before implementing.
- Record the chosen API version in `MEMORY.md`.
EOF

write_file ".claude/rules/ai.md" <<'EOF'
# AI Rules - EasyPost 2.0

## Architecture
- AI calls belong behind backend services/adapters.
- Keep `AI_PROVIDER=mock` usable for local development and tests.
- Persist prompts/outputs only when there is a product or debugging reason.

## Product
- Generated content must be reviewable before publishing.
- Keep approval and publication status explicit.
- Do not silently publish AI output without the approved workflow.

## Safety and privacy
- Do not send secrets or unnecessary personal data to AI providers.
- Make provider errors visible as actionable statuses.
- Prefer deterministic tests with mock providers.
EOF

write_file ".claude/skills/qa.md" <<'EOF'
# QA Skill - EasyPost 2.0

Voce e um QA Engineer senior.

## Quando atuar
- Antes de codar uma feature nova.
- Depois que uma feature for implementada.
- Antes de considerar uma tarefa concluida.

## Antes da implementacao
- Identificar riscos.
- Listar cenarios de teste.
- Definir testes unitarios necessarios.
- Definir testes de integracao/API necessarios.
- Definir regressao minima.

## Depois da implementacao
- Conferir se os testes foram criados.
- Verificar riscos de regressao.
- Sugerir casos nao cobertos.
- Confirmar checklist de aceite.

## Checklist obrigatorio
- O fluxo feliz funciona?
- Existem testes para erros comuns?
- Existem testes para validacoes?
- Endpoints retornam status HTTP correto?
- O mobile trata loading, empty e error?
- Webhooks sao idempotentes quando aplicavel?
- Nenhum secret/token foi logado ou commitado?
EOF

write_file ".agents/README.md" <<'EOF'
# Agents - EasyPost 2.0

Este diretorio guarda skills e instrucoes reutilizaveis para agentes.

Use:
- `.agents/skills/stripe-best-practices` para qualquer trabalho de Stripe.
- `.agents/skills/upgrade-stripe` ao atualizar SDK/API version.
- `.claude/skills/qa.md` para planejamento e revisao de QA.

Antes de criar uma nova skill, procure por uma existente para evitar duplicidade.
EOF

write_file ".agents/skills/stripe-best-practices/SKILL.md" <<'EOF'
---
name: stripe-best-practices
description: >
  Guides Stripe integration decisions for EasyPost 2.0: subscriptions, Checkout,
  Billing, webhooks, API key handling, webhook idempotency and mobile-safe Stripe
  architecture.
---

# Stripe Best Practices

Use this skill when building, modifying or reviewing Stripe integration.

## Defaults
- Prefer Checkout Sessions + Billing for subscriptions.
- Keep Stripe secret keys only on the Rails backend.
- Prefer restricted API keys when possible.
- Verify webhook signatures.
- Persist processed webhook event ids for idempotency.
- Sync subscription state from webhooks.
- Never log card data, secrets, JWTs or webhook secrets.
- Do not send Stripe secret keys to the mobile app.

## API version
- Verify the current Stripe API version in official Stripe docs before implementation.
- Record the chosen version in `MEMORY.md`.

## Before coding
Read the relevant reference:
- `references/billing.md`
- `references/security.md`
- `references/mobile.md`
- `references/webhooks.md`
EOF

write_file ".agents/skills/stripe-best-practices/references/billing.md" <<'EOF'
# Stripe Billing Reference

## Recommended MVP path
- Use Stripe Checkout for subscription creation.
- Use Customer Portal for plan management/cancellation unless a custom flow is required.
- Store `stripe_customer_id`, `stripe_subscription_id`, plan/price ids and local subscription status.
- Treat success/cancel redirects as UX hints only; webhook events are authoritative.

## Events to consider
- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`

## Tests
- request specs for checkout/session creation
- webhook specs for each subscription transition
- idempotency test for repeated webhook events
EOF

write_file ".agents/skills/stripe-best-practices/references/security.md" <<'EOF'
# Stripe Security Reference

- Use restricted API keys when possible.
- Never expose secret keys to mobile.
- Keep webhook signing secrets in environment variables.
- Verify all webhook signatures.
- Avoid logging raw webhook bodies after verification unless sanitized.
- Never commit `.env` or generated secret files.
- Use HTTPS in production.
EOF

write_file ".agents/skills/stripe-best-practices/references/mobile.md" <<'EOF'
# Stripe Mobile Reference

- Mobile should request checkout/customer-portal URLs or ephemeral client data from the backend.
- Mobile must not contain Stripe secret keys.
- Store auth tokens in secure platform storage.
- Show clear billing status, loading and error states.
- Backend remains authoritative for subscription access.
EOF

write_file ".agents/skills/stripe-best-practices/references/webhooks.md" <<'EOF'
# Stripe Webhooks Reference

## Required properties
- Verify signatures.
- Store event ids.
- Make handlers idempotent.
- Handle duplicate and out-of-order events.
- Return 2xx only after successful processing or safe idempotent acknowledgement.

## Suggested model fields
- provider
- event_id
- event_type
- processed_at
- processing_status
- error_message
EOF

write_file ".agents/skills/upgrade-stripe/SKILL.md" <<'EOF'
---
name: upgrade-stripe
description: Guide for upgrading Stripe API versions and SDKs in EasyPost 2.0.
---

# Upgrade Stripe

Use this skill before changing Stripe SDK or API versions.

## Checklist
1. Check official Stripe changelog and upgrade guide.
2. Identify current API version in code and `MEMORY.md`.
3. Update backend SDK.
4. Set/confirm explicit API version in Stripe client initialization.
5. Review webhook payload changes.
6. Run billing and webhook specs.
7. Update `MEMORY.md` with the new version and date.

## Rules
- Do not rely only on account default API version.
- Do not change API version and billing behavior in the same unreviewed step.
- Webhook handlers must tolerate unknown event types.
EOF

write_file ".codex/README.md" <<'EOF'
# Codex Notes - EasyPost 2.0

Codex should use:
- `AGENTS.md` for project-level instructions.
- `MEMORY.md` for durable decisions and historical context.
- `.claude/rules/*` as reusable engineering rules even outside Claude.
- `.agents/skills/*` for domain-specific guidance.

Do not duplicate memory in this directory. Keep the source of truth at `MEMORY.md`.
EOF

write_file "modules/README.md" <<'EOF'
# Modules - EasyPost 2.0

Use this directory for module-specific context only when the product area becomes large enough to need it.

Suggested future modules:
- auth
- companies
- profiles
- posts
- ai
- scheduling
- publishing
- billing

Each module may contain:
- `README.md`: purpose and responsibilities
- `agents/`: conceptual agents
- `skills/`: reusable skills
- `rules/`: module constraints
- `memory.md`: module-specific decisions, only when root `MEMORY.md` is too broad

Avoid creating module folders before they are useful.
EOF

write_file "docs/ai-harness.md" <<'EOF'
# AI Harness

This project uses a lightweight AI harness to keep agents consistent across sessions.

## Files
- `AGENTS.md`: main working agreement.
- `CLAUDE.md`: root pointer for Claude.
- `MEMORY.md`: durable decisions and context.
- `.claude/CLAUDE.md`: Claude-specific project instructions.
- `.claude/rules/*`: reusable engineering rules.
- `.claude/skills/qa.md`: QA checklist.
- `.agents/skills/*`: domain skills, including Stripe.
- `.codex/README.md`: Codex notes.
- `modules/README.md`: future module harness guidance.

## Maintenance
- Update `MEMORY.md` whenever architecture, product scope, integration choices or naming conventions become durable.
- Keep secrets out of every harness file.
- Prefer adapting existing skills/rules before creating new ones.
EOF

echo
echo "EasyPost AI harness bootstrap complete."
echo "Next steps:"
echo "1. Review MEMORY.md and fill pending decisions."
echo "2. Run git diff before committing."
echo "3. Keep .claude/settings.local.json out of git if Claude creates it."
