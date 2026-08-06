# Funil Android Externo

Bloco do painel admin que responde uma única pergunta:

> Entre as instalações externas dos builds instrumentados, onde as pessoas mais
> abandonam **antes** de criar a conta?

- Serviço: `api/app/services/analytics/android_funnel.rb`
- Endpoints: `GET /api/v1/admin/analytics/android_funnel` e
  `GET /api/v1/admin/analytics/android_funnel/installations?stage=…`
- UI: `web/src/app/(app)/admin/android-funnel-section.tsx`, renderizada abaixo do
  bloco "App Android" em `/admin`.

Não confundir com `Analytics::AndroidInstallations` ("App Android"), que mede a
base instalada histórica, nem com o `user_funnel` daquele serviço, que mede o que
os usuários **já vinculados** fizeram depois.

---

## Etapas

A unidade de toda etapa é **`installation_id` distinto**, obtido por
`GROUP BY properties->>'installation_id'`. Uma instalação que emitiu
`app_opened` sete vezes é uma instalação naquela etapa — por construção, não por
um filtro que alguém precisa lembrar de escrever.

| Etapa | Eventos |
|---|---|
| Instalações observadas | linha em `app_installations` na coorte |
| First open | `app_first_open` |
| Session started | `session_started` |
| Entrada visualizada | `native_entry_viewed`, `landing_page_viewed` |
| Tela de autenticação | `auth_screen_viewed` |
| Escolheu login/cadastro | `signup_selected`, `login_selected` |
| Tentou autenticar | `auth_provider_clicked` |
| Auth iniciada no cliente | `social_login_started`, `signup_started`, `login_started` |
| Auth chegou à API | `google_auth_started`, `android_registration_started`, `email_auth_started` |
| Auth concluída | `google_auth_succeeded`, `android_registration_succeeded`, `signup_completed`, `email_auth_succeeded` |
| **Usuários Android criados** | `users.signup_source = 'android'` — **métrica de usuários** |
| Instalação vinculada | `installation_link_succeeded` **ou** `app_installations.user_id` |

Observações que evitam leituras erradas:

- `session_started` é o evento **nativo**. O equivalente web/PWA é
  `web_session_started` e não entra: este funil é Android nativo.
- **Não existe** `email_signup_started` nem `email_login_started` no produto. O
  fluxo de e-mail emite `signup_started` / `login_started` com `method: "email"`,
  já cobertos por "Auth iniciada no cliente". Do lado do servidor, quem responde
  por ele é `email_auth_started` / `email_auth_succeeded` — o equivalente exato
  de `google_auth_*`. Antes disso o e-mail parava em "iniciou no cliente" para
  sempre, porque nenhum evento do servidor dizia que a requisição tinha chegado.
- "Usuários Android criados" é medida em **usuários**. Nunca é dividida por, nem
  comparada com, uma contagem de instalações — a UI a marca com um selo.
- As etapas **não são forçadas a ser monotônicas**. Se uma etapa superar a
  anterior (instrumentação faltando em algum ponto), o `MetricResult` devolve
  `status: "inconsistent"` em vez de mascarar o problema.

### Dentro de "iniciou no cliente e não chegou à API"

Esse balde juntava três coisas diferentes, e somar cancelamento com erro fazia
uma decisão do usuário parecer defeito — além de esconder o tamanho real do
defeito. O payload traz `stopped_auth_client_breakdown`, também em instalações
distintas:

| Chave | Significado |
|---|---|
| `cancelled_auth` | tem `social_login_failed` com `failure_category: "user_cancelled"` |
| `technical_failure` | tem `auth_client_error`, `login_failed`, ou `social_login_failed` de outra categoria |
| `no_outcome` | iniciou e não produziu desfecho nenhum |

A precedência é deliberada: havendo falha técnica, é isso que precisa ser
consertado, mesmo que a pessoa também tenha cancelado em alguma tentativa.

---

## Coorte: por que só build >= 51

Builds anteriores não carregam `installation_id` nos eventos e nunca emitiram
`auth_screen_viewed` nem `signup_selected`/`login_selected`. Incluí-los reportaria
"abandono" de uma etapa que não podia ser alcançada.

```ruby
Analytics::AndroidFunnel.min_instrumented_build  # => 51
```

Limiar lido em tempo de chamada de `ANDROID_FUNNEL_MIN_BUILD`, com default 51 **no
código**: um env ausente no servidor nunca pode desligar silenciosamente o corte.
Valor malformado cai no default.

Instalações com `app_build` nulo ou não numérico ficam **fora** (não há como
afirmar que são >= 51) e são reportadas em
`cohort.excluded.missing_or_invalid_build`, para o total continuar reconciliável.

Períodos (`period`): `since_instrumentation` (padrão, sem limite inferior de data —
o corte é o build), `today`, `7d`, `30d`. Janelas cortadas em
`Analytics::ReportingTime.zone` (America/Sao_Paulo), nunca em UTC.

---

## Classificação de público

Reusa `Analytics::AccountClassification` — identidade, nunca dispositivo
(`manufacturer = "Google"` é rejeitado como critério: um Pixel é um aparelho
Google de uma pessoa real).

| Instalação | Classificação |
|---|---|
| com `user_id` | `AccountClassification.for(user)` |
| anônima, com evento atribuído a conta `@cloudtestlabaccounts.com` | `automated_test` |
| anônima, sem evidência | **`external`** |

Filtro `audience`: `external` (padrão), `internal_test`, `all`.

**Limitação conhecida:** uma execução do Google Test Lab que instala, navega e
**não** cria conta é indistinguível de um usuário externo anônimo, e entra como
externa. Não há evidência segura disponível para separá-la, e inventar uma seria
pior do que declarar o limite.

---

## O caso `conflict`

Aparelho já pertencente à conta A, no qual a conta B se cadastra: o vínculo de B
falha com `user_conflict` e a linha mantém o `user_id` de A.

No funil isso conta como **auth concluída** e **usuário criado**, mas **não** como
instalação vinculada — a instalação cai no bucket "autenticou e não vinculou", com
`link_result = "conflict"` na lista de investigação. O código de falha é limpo em
um vínculo bem-sucedido, então sua presença significa que a **última** tentativa é
a que falhou.

`link_failures` reporta cada código separadamente (`user_conflict`,
`installation_not_found`, demais → `error`).

> Este é um problema **secundário**. Ele não explica o volume histórico de
> instalações anônimas, e as duas coisas são medidas separadamente no painel.

---

## Dados históricos

O inventário histórico (~800 instalações) **não** é usado para calcular etapas que
não existiam antes da instrumentação. Não há backfill nem heurística. Os números
históricos permanecem no bloco "App Android".

---

## Performance

A agregação acontece toda no banco; nenhum `ProductAnalyticsEvent` é carregado em
Ruby para ser filtrado com `select`. O resultado tem no máximo uma linha por
instalação.

**Não há migration neste item.** Não existe índice em
`properties->>'installation_id'`; a query se apoia em
`index_product_analytics_events_on_event_name_and_occurred_at` (14 de 105 nomes de
evento) e no índice único `app_installations.installation_id`.

Medir na VPS **antes** de qualquer conversa sobre índice:

```bash
docker compose exec db psql -U postgres -d easy_health_production -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT e.properties->>'installation_id' AS installation_id,
       COUNT(*) FILTER (WHERE e.event_name = 'app_first_open')      AS s_first_open,
       COUNT(*) FILTER (WHERE e.event_name = 'session_started')     AS s_session_started,
       COUNT(*) FILTER (WHERE e.event_name IN ('native_entry_viewed','landing_page_viewed')) AS s_entry_viewed,
       COUNT(*) FILTER (WHERE e.event_name = 'auth_screen_viewed')  AS s_auth_screen,
       MAX(e.occurred_at) AS last_event_at
FROM product_analytics_events e
WHERE e.event_name IN (
        'app_first_open','session_started','native_entry_viewed','landing_page_viewed','auth_screen_viewed',
        'signup_selected','login_selected','auth_provider_clicked',
        'social_login_started','signup_started',
        'login_started','google_auth_started','android_registration_started',
        'google_auth_succeeded','android_registration_succeeded','signup_completed',
        'installation_link_succeeded')
  AND e.properties->>'installation_id' IN (
        SELECT installation_id FROM app_installations
        WHERE platform = 'android'
          AND (CASE WHEN app_build ~ '^[0-9]{1,9}\$' THEN app_build::int END) >= 51)
GROUP BY 1;"
```

Só com esse custo em mãos é que se abre um item separado propondo o índice mínimo
(`CREATE INDEX CONCURRENTLY … ON product_analytics_events ((properties->>'installation_id'))`),
apresentando query, EXPLAIN e custo como evidência.

---

## Como achar o maior abandono

`biggest_drop` percorre pares consecutivos de etapas **de instalação** (a etapa de
usuários fica de fora) e devolve a maior perda absoluta, com `lost` e `drop_rate`.
A UI mostra isso como **"Maior abandono observado"** — descritivo. Onde as pessoas
param de ser observadas não é o mesmo que por que elas pararam.

Para investigar: abra o bucket correspondente em "Instalações por última etapa" e
clique numa instalação; o link leva a
`/admin/observability?installation_id=<id>`, que abre a timeline já preenchida.

---

## Testes

```bash
cd api && DB_HOST=localhost DB_PORT=5433 DB_USERNAME=postgres DB_PASSWORD='…' \
  RAILS_ENV=test bundle exec rspec \
  spec/services/analytics/android_funnel_spec.rb \
  spec/requests/api/v1/admin/android_funnel_spec.rb

cd web && npx vitest run src/__tests__/android-funnel-section.test.tsx
```
