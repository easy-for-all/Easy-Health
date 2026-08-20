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
`app_resumed`, `app_backgrounded`, `app_updated`, `installation_id_regenerated`,
`web_session_started`, `pwa_installed`,
`deep_link_opened`, `landing_page_viewed`, `native_entry_viewed`, …), **Autenticação** (`signup_*`, `login_*`,
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

No Android o app é um shell Capacitor que carrega o site, então a
**primeira tela pré-auth é a entrada nativa nos builds novos ou a landing em
builds antigos**, não uma tela de acesso. Entre o boot e a
chegada da requisição no Rails não havia nenhum sinal: uma instalação que abriu e
saiu era idêntica a uma que tocou no Google e falhou no aparelho.

| Evento | Significado exato | Quem emite |
|---|---|---|
| `app_first_open` / `app_opened` / `session_started` | boot nativo | frontend (`analytics/lifecycle.ts`) |
| `landing_page_viewed` | landing comercial renderizada na web ou em builds Android antigos | frontend (`app/page.tsx`) |
| `native_entry_viewed` | tela curta de entrada nativa renderizada no Android | frontend (`NativeEntryScreen`) |
| `auth_screen_viewed` | `/login` ou `/sign-up` renderizada e utilizável | frontend (`useAuthScreenView`) |
| `signup_selected` / `login_selected` | escolha explícita de cadastro/entrada | frontend (CTAs) |
| `signup_started` / `login_started` | formulário **enviado**, após validação client | frontend (submit) |
| `social_login_started` | **toque** no botão do provedor | frontend (telas de auth) |
| `social_login_failed` | desfecho terminal da tentativa social, **inclusive cancelamento** (traz `failure_category`) | frontend |
| `social_login_completed` | a tentativa social terminou com sessão (nativo) | frontend |
| `login_completed` / `signup_completed` | a tentativa por e-mail terminou com sessão | frontend |
| `auth_client_error` | erro client-side real (plugin, rede), **nunca** cancelamento | frontend |
| `auth_api_error` | a API **respondeu** erro (traz `http_status`) | frontend |
| `google_auth_started` | a **requisição chegou** em `POST /auth/google/native` | backend |
| `email_auth_started` | a **requisição chegou** em `/auth/sign_in` ou `/auth/sign_up` | backend |
| `email_auth_succeeded` / `email_auth_failed` | desfecho da requisição por e-mail no servidor | backend |
| `android_registration_started` | a mesma requisição, com `terms_accepted` | backend |
| `installation_link_succeeded` | instalação vinculada ao usuário | backend |

⚠️ `android_registration_started` **não é** abertura de tela nem clique: é o
recebimento da requisição no servidor, já com o `id_token` do Google em mãos.
Quem toca no botão e cancela o seletor de contas produz `social_login_started`
sem nunca produzir `google_auth_started` — é assim que essa perda vira número.

### Cancelamento não é erro

`social_login_failed` é o único evento emitido quando a pessoa fecha o seletor de
contas: `failure_category: "user_cancelled"`, `error_code: "USER_CANCELLED"`.
**Não** sai `auth_client_error` e **nada** vai para o Sentry — o Admin mostra isso
como saída deliberada, em cinza, nunca em vermelho.

O cancelamento é reconhecido **só por código** (`USER_CANCELLED`/`cancelled`,
contrato do `@capgo/capacitor-social-login`). Ler a mensagem, como antes, fazia
qualquer falha cujo texto mencionasse "cancel" sumir das contagens de falha.

`failure_category` é vocabulário fechado, validado em `Analytics::Ingestion`:
`user_cancelled`, `provider_error`, `oauth_configuration_error`, `network_error`,
`timeout`, `backend_error`, `invalid_credentials`, `validation_error`,
`rate_limited`, `unknown`.

### Correlação por tentativa: `auth_attempt_id`

Todo evento de uma mesma tentativa (do clique ao desfecho) carrega o mesmo
`auth_attempt_id`, gerado no cliente (`shared/lib/auth-attempt.ts`) e enviado ao
backend no header `X-Auth-Attempt-Id`. É opaco, aleatório e **opcional**: sem ele
a requisição é atendida igual, apenas não dá para juntar as duas metades. Uma
nova tentativa depois de um cancelamento ou de uma falha **sempre** gera um id
novo — reaproveitar faria uma pessoa insistindo parecer várias pessoas.

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

> **Entre `workout_started` e `workout_first_exercise_started` existe a tela de
> aquecimento.** Em `/workout/today`, `startWorkout()` leva a `phase = "warmup"`;
> `workout_first_exercise_started` só dispara quando `phase === "exercising"`, ou
> seja, **depois do "Estou pronto →"**. Quem inicia e não passa do aquecimento
> aparece no funil como "iniciou e não chegou ao primeiro exercício" — o degrau
> perdido é a tela de aquecimento, não o exercício. Não há evento próprio para
> essa transição; ao ler esse intervalo, não a interprete como desistência
> diante do exercício.

## Duas superfícies de execução — o funil NÃO é universal

Existem duas telas onde um treino é executado, e elas têm unidades diferentes.
Ler as duas no mesmo funil produz zeros que são artefato de instrumentação, não
comportamento.

| | Autenticada | Anônima |
|---|---|---|
| Rota | `/workout/today` | `/plano/treino` |
| `source` | `workout_today` | `anonymous` |
| Unidade | exercício → **série** → peso → reps | exercício com checkbox |
| `exercise_set_completed` | sim | **impossível — não existe série** |
| `workout_started` | clique deliberado | `useEffect` a cada montagem |

`exercise_set_completed` **não serve como degrau universal**: na tela anônima ele
nunca poderá existir. Sintetizá-lo a partir de um checkbox seria fabricar dado.

> **`workout_exercise_completed` conta exercícios individuais nas duas
> superfícies.** Na anônima, um por checkbox marcado. Na autenticada, um por
> exercício concluído — inclusive dentro de blocos compostos: `finishExercise`
> roda uma vez só, no último membro do bloco, então a emissão percorre os membros
> e usa o mesmo critério que decide `skipped_exercises` no payload salvo
> (`hasExerciseProgress`, em `features/workout/set-completion.ts`). Um superset de
> 3 exercícios concluídos produz 3 eventos. Exercício pulado ou nunca alcançado
> não emite.

**Funil cross-surface** (o único comparável):

```
workout_created → workout_viewed → workout_start_clicked → workout_started
→ workout_first_exercise_started → workout_exercise_completed → workout_completed
```

**Detalhado, só `source = workout_today`** — é onde peso, séries e progressão de
carga podem ser investigados:

```
workout_first_exercise_started → exercise_set_completion_attempted
→ exercise_set_completed → workout_exercise_completed → workout_completed
```

**Detalhado, só `source = anonymous`:**

```
workout_first_exercise_started → workout_exercise_completed → workout_completed
```

Sempre segmente por `properties->>'source'` antes de comparar etapas.

## `workout_viewed` — semântica canônica

**"O usuário visualizou conteúdo concreto do treino criado"** — e não "entrou em
`/workout/today`". Qualquer tela que mostre o treino gerado (nome, exercícios,
grupos musculares) emite, com `source` próprio:

| `source` | Tela |
|---|---|
| `workouts_ready` | `/workouts/ready` — destino padrão pós-onboarding autenticado |
| `anonymous_ready` | `/plano/pronto` — equivalente da variante `open_app` |
| `workout_today` | `/workout/today` — execução |

Uma pessoa pode emitir mais de um numa jornada: os funis contam **instalações
distintas**, não eventos, então isso não infla nenhuma etapa.

`activation_ready_screen_viewed` é outra coisa e continua existindo — vive no
pipeline `onboarding_events`, com objetivo e painel próprios.

> **Descontinuidade conhecida:** `/workouts/ready` não emitia `workout_viewed`,
> enquanto `/plano/pronto` emitia. Enquanto isso durou, a métrica
> "1º treino visualizado" do painel post-onboarding esteve **enviesada a favor
> da variante `open_app`** por instrumentação, não por comportamento — e quem via
> o treino na ready screen sem prosseguir era contado como "nunca viu o treino".
> Leituras que atravessem a data da correção não são comparáveis.

## Versionamento

Mudança incompatível no schema de um evento → incrementar `version` na YAML (e no
espelho TS). O envelope guarda `event_version` para permitir consultas por versão.
