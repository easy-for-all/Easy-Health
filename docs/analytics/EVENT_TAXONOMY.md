# Event Taxonomy — EasyHealth

**Fonte única de verdade:** [`api/config/analytics/events.yml`](../../api/config/analytics/events.yml).
O backend valida a ingestão contra ela (`Analytics::EventCatalog`) e o frontend
espelha os nomes em `web/src/shared/lib/analytics/taxonomy.ts` (gerado da mesma
YAML; um teste de paridade — `analytics-taxonomy.test.ts` — falha se divergirem).

## Sinks

- **server** — persistido em `product_analytics_events` (auditável, alimenta o Admin).
- **ga4** — enviado ao Google Analytics 4 (exploração comportamental).
- **clarity** — emitido como custom event/tag do Microsoft Clarity (diagnóstico).

## Envelope de cada evento

Todo evento carrega: `event_name`, `event_version`, `occurred_at`, `received_at`
(servidor), `anonymous_id` (antes do login), `user_id` (quando autenticado, **setado
no servidor**), `session_id`, `platform`, `app_surface`, `app_version`, `build_number`,
`environment`, `locale`, `timezone`, `source`, `properties`, `idempotency_key`.

### Enums obrigatórios

- `platform`: `android` · `web` · `pwa` · `unknown`
- `app_surface`: `native_shell` · `mobile_web` · `desktop_web` · `installed_pwa` · `browser_pwa` · `unknown`
- `environment`: `production` · `staging` · `development` · `test`

## Proibido em `properties`

senha, token, texto integral de exames, fotos, conteúdo médico, nome completo,
e-mail, telefone, endereço, coordenada GPS, dados sensíveis livres, resposta
completa de IA. Sanitização automática via `RelationshipEventTracker::SENSITIVE_KEY_PATTERN`
(chaves com `password|token|secret|authorization|card|stripe|cpf|ssn|cvv|cvc|dsn|api_key|access_key`).

Idade/peso/limitação/objetivo **não** devem ser repetidos em todos os eventos —
usar dimensões agregadas apenas quando seguro.

## Eventos (v1)

Grupos definidos na YAML: **Aquisição & lifecycle** (`app_first_open`, `app_opened`,
`app_resumed`, `app_backgrounded`, `app_updated`, `web_session_started`, `pwa_installed`,
`deep_link_opened`, `landing_page_viewed`, …), **Autenticação** (`signup_*`, `login_*`,
`social_login_*`), **Onboarding** (`onboarding_*`), **Treinos** (`workout_created`,
`workout_viewed`, `workout_start_clicked`, `workout_started`, `workout_first_exercise_started`,
`workout_abandoned`, `workout_completed`, …), **Engajamento**, **Push** (`push_*`,
`workout_started_after_push`, `workout_completed_after_push`), **Assinatura**
(`paywall_viewed`, `checkout_*`, `subscription_*`, `trial_*`), **Experimentos**
(`experiment_assigned/exposed/converted`) e **Erros funcionais** (`analytics_event_rejected`,
`deep_link_failed`, `workout_load_failed`, `workout_save_failed`, `push_registration_failed`).

Para a lista canônica e os sinks de cada evento, **consulte sempre a YAML** — ela é
a fonte, este documento é o guia.

## As 4 ações de treino NÃO são a mesma coisa

| Evento | Significado | Sinal técnico |
|---|---|---|
| `workout_start_clicked` | clicou para iniciar | clique de UI |
| `workout_started` | sessão criada | `WorkoutSession` criada (`workout_sessions_controller#start`) |
| `workout_first_exercise_started` | 1º exercício iniciado | `exercise_sessions` / progresso |
| `workout_completed` | concluído válido | `completion_status = "completed"` |

## Versionamento

Mudança incompatível no schema de um evento → incrementar `version` na YAML (e no
espelho TS). O envelope guarda `event_version` para permitir consultas por versão.
