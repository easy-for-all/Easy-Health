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

## Funil pré-auth Android — quem dispara o quê

No Android o app é um shell Capacitor que carrega o site na raiz, então a
**primeira tela é a landing page**, não uma tela de acesso. Entre o boot e a
chegada da requisição no Rails não havia nenhum sinal: uma instalação que abriu e
saiu era idêntica a uma que tocou no Google e falhou no aparelho.

| Evento | Significado exato | Quem emite |
|---|---|---|
| `app_first_open` / `app_opened` / `session_started` | boot nativo | frontend (`analytics/lifecycle.ts`) |
| `landing_page_viewed` | landing renderizada (1ª tela no Android) | frontend (`app/page.tsx`) |
| `auth_screen_viewed` | `/login` ou `/sign-up` renderizada e utilizável | frontend (`useAuthScreenView`) |
| `signup_selected` / `login_selected` | escolha explícita de cadastro/entrada | frontend (CTAs) |
| `signup_started` / `login_started` | formulário **enviado**, após validação client | frontend (submit) |
| `social_login_started` | **toque** no botão do provedor | frontend (telas de auth) |
| `social_login_failed` | falhou **no aparelho**, sem chegar na API | frontend |
| `auth_client_error` | erro client-side real (plugin, rede) | frontend |
| `auth_api_error` | a API **respondeu** erro (traz `http_status`) | frontend |
| `google_auth_started` | a **requisição chegou** em `POST /auth/google/native` | backend |
| `android_registration_started` | a mesma requisição, com `terms_accepted` | backend |
| `installation_link_succeeded` | instalação vinculada ao usuário | backend |

⚠️ `android_registration_started` **não é** abertura de tela nem clique: é o
recebimento da requisição no servidor, já com o `id_token` do Google em mãos.
Quem toca no botão e cancela o seletor de contas produz `social_login_started`
sem nunca produzir `google_auth_started` — é assim que essa perda vira número.

## Correlação por `installation_id`

Todo evento nativo carrega `properties.installation_id` (sem coluna nova). No
frontend ele entra em `analytics/server.ts`; no backend, `Analytics::Ingestion`
preenche a partir de `Observability::Context` quando o corpo não trouxe (o flush
por `sendBeacon` não carrega headers). É correlação operacional apenas: nunca
substitui `anonymous_id` e nunca é identificador de pessoa.

```ruby
ProductAnalyticsEvent.where("properties->>'installation_id' = ?", id).order(:occurred_at)
```

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
