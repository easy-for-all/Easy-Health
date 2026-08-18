# Security Status — easyhealth.art

**Avaliado em:** 2026-08-18  
**Scan mais recente:** 2026-08-18 (Local Pentest Agent) · 10 achados · 0 críticos · 0 altos · 1 médio · 1 baixo  
**Status atual:** os 2 achados do scan externo são não-achados já tratados desde 2026-07-05. A investigação do que o scanner **não** alcança encontrou uma lacuna estrutural de CI, agora corrigida, e 98 advisories de gem + 10 vulnerabilidades npm, todas resolvidas.

---

## Resumo

| Achado | Severidade | Status |
|--------|------------|--------|
| Certificado TLS expira em 55 dias | Médio | ✅ Não-achado — Cloudflare Universal SSL + monitoramento diário |
| Header `Server` expõe software do servidor | Baixo | ⚠️ Residual Cloudflare aceito/documentado |
| `api/.github/` inerte — CI de segurança nunca executou | **Alto (interno)** | ✅ Migrado para a raiz e bloqueante |
| 98 advisories de gem (bundler-audit) | Alto | ✅ Gems atualizadas — 0 advisories |
| 10 vulnerabilidades npm (8 high) | Alto | ✅ Next 16.3.1 + `npm audit fix` — 0 vulnerabilidades |
| 27 warnings Brakeman nunca revisados | Médio | ✅ 9 corrigidos no código, 18 falsos positivos com nota |
| `connect-src` liberava qualquer host HTTPS | Médio | ✅ Curinga `https:` removido; allowlist real |
| CSP sem `base-uri` / `form-action` | Baixo | ✅ Ambas adicionadas |
| Exposição direta da origem (portas 3000/3001) | A confirmar | ⚠️ Requer verificação no VPS — ver seção própria |

---

## 🔎 Avaliação do scan de 2026-08-18

O relatório do Local Pentest Agent trouxe os mesmos 2 itens já avaliados em 2026-07-05.
Nenhum dos dois é acionável:

- **TLS expira em 55 dias.** O certificado observado é da borda Cloudflare (issuer
  Let's Encrypt `YE1`, `notAfter` 2026-10-12) para `easyhealth.art` e `api.easyhealth.art`.
  É o ciclo normal de 90 dias do Universal SSL, com renovação automática. O
  monitoramento recorrente descrito abaixo continua ativo e, com 55 dias restantes,
  corretamente **não** dispara (`WARN_DAYS=45`).
- **Header `Server`.** Continua sendo `server: cloudflare`, da borda. Segue como
  residual aceito — ver seção própria.

> Um scanner externo só enxerga a borda da Cloudflare. Os achados reais desta rodada
> vieram de olhar o que ele não alcança: o CI, as dependências e a CSP.

---

## ✅ Tratados

### [ALTO — interno] `api/.github/` inerte: o CI de segurança nunca executou

**Status:** corrigido em 2026-08-18.

`api/.github/workflows/ci.yml` e `api/.github/dependabot.yml` existiam, mas o GitHub
Actions só lê `.github/workflows/` da **raiz** do repositório e o Dependabot só lê
`.github/dependabot.yml` da raiz. Como `api/` não é submódulo (o único em `.gitmodules`
é `external/free-exercise-db`), esses arquivos eram código morto: **Brakeman,
bundler-audit e RuboCop nunca rodaram uma única vez**, e o Dependabot nunca abriu um PR.

O sintoma era silencioso por natureza — um job que não existe não falha.

**Implementado:**

- Os dois arquivos foram removidos e o conteúdo útil migrou para
  `.github/workflows/pr-check.yml`, que já era o gate de PR conhecido (evita um segundo
  workflow com trigger quase idêntico).
- Quatro jobs novos, todos **bloqueantes**: `brakeman`, `bundler-audit`, `rubocop`,
  `npm-audit`. Reutilizam o padrão Ruby que o próprio `pr-check.yml` já usava
  (`defaults.run.working-directory: api` + `ruby/setup-ruby` com `working-directory`).
- `.github/dependabot.yml` criado na raiz, cobrindo os três ecossistemas do monorepo:
  `bundler` → `/api`, `npm` → `/web` (que **não existia** antes) e `github-actions` → `/`.

> Os `continue-on-error` pré-existentes dos jobs `lint`, `vitest` e `rspec` foram
> mantidos como estavam — são dívida conhecida e documentada, fora do escopo desta rodada.

---

### [ALTO] 98 advisories de gem (bundler-audit)

**Status:** corrigido — `bundler-audit check` sai limpo.

`bundler-audit` **não estava no `Gemfile`**: o binstub `bin/bundler-audit` era órfão e o
step do CI morto teria falhado com `LoadError` de qualquer forma. Depois de adicionar a
gem, a primeira execução real acusou **98 advisories**.

Corrigido com atualização de patch dentro das restrições já declaradas no `Gemfile`
(`bundle update`, sem afrouxar nenhuma versão):

| Gem | De | Para |
|-----|----|----|
| rails / activestorage / actionpack … | 8.1.3 | 8.1.3.1 |
| nokogiri | 1.19.3 | 1.19.4 |
| puma | 8.0.1 | 8.0.2 |
| websocket-driver | 0.8.0 | 0.8.2 |
| concurrent-ruby | 1.3.6 | 1.3.7 |
| devise | 5.0.3 | 5.0.4 |
| faraday | 2.14.1 | 2.14.3 |
| loofah / rails-html-sanitizer / crass / json / msgpack / net-imap | — | patch |

Suíte revalidada depois da atualização: sem regressão (ver seção de validação).

---

### [ALTO] 10 vulnerabilidades npm (8 high)

**Status:** corrigido — `npm audit` sai com 0 vulnerabilidades.

Nenhum CI auditava o `web/`. A baseline tinha 10 vulnerabilidades em 9 pacotes, todas
transitivas:

- `sharp` (<0.35.0 — 4 CVEs de libvips) e `postcss` (<=8.5.22 — 4 advisories), ambos
  vindos do Next e resolvidos pelo bump **16.2.4 → 16.3.1** (não é major).
- `undici`, `js-yaml`, `nanoid`, `fast-uri`, `brace-expansion` (high), `tar` (moderate) e
  `@babel/core` (low), resolvidos por `npm audit fix` **sem `--force`**.

O pin exato de `next` foi preservado (`"16.3.1"`, sem `^`). O diff do `package-lock.json`
foi inspecionado: 62 pacotes mudaram de versão, **0 bumps de major**.

---

### [MÉDIO] 27 warnings do Brakeman nunca revisados

**Status:** revisados um a um. `bundle exec brakeman` sai com **0 warnings** e 18
ignorados conscientemente.

Não foi gerado baseline cego. Dos 27 (3 High, 22 Medium, 2 Weak):

**9 corrigidos no código**, trocando interpolação por `sanitize_sql_array` com bind
parameters ou pela API correta do ActiveRecord — o que eliminou **os 3 High**:

- `analytics/event_orchestration.rb` (3×) — listas `IN (...)` montadas por interpolação
  de constante.
- `analytics/android_funnel.rb` — `auth_outcomes` passou a montar a query inteira com
  bind parameters.
- `block_usage_metrics_service.rb` (2×) — `ANY(ARRAY[...])` com bind.
- `quick_workouts_controller.rb` e `workout_intelligence/exercise_candidate_scope.rb` —
  ordenação por favoritos; no controller a duplicação virou o helper `fav_priority_order`.
- `lib/observability/bi_views.rb` (2×) — `quote_table_name` no `DROP VIEW` e bind no
  `LEFT(viewname, ?)`.

**18 falsos positivos** em `api/config/brakeman.ignore`, cada um com nota específica
dizendo a origem do valor, por que não é controlável pelo usuário e qual coerção,
whitelist ou `connection.quote` já existe. São quatro padrões: fragmento SQL vindo de
constante congelada (`NUMERIC_BUILD_SQL`, `ReportingTime.local_date_sql`), whitelist de
código, valores já passados por `connection.quote`, e subqueries geradas por
`relation.to_sql`.

O job do CI roda com `--ensure-ignore-notes` e `--ensure-no-obsolete-ignore-entries`, de
modo que o arquivo não pode virar depósito silencioso: entrada sem justificativa ou que
não corresponde mais a um warning real quebra o build.

---

### [MÉDIO] `connect-src` liberava qualquer host HTTPS

**Status:** corrigido em `web/next.config.ts`.

A diretiva era `connect-src 'self' https: https://www.google-analytics.com …`. O `https:`
sozinho autoriza conexão a **qualquer** host HTTPS, o que tornava decorativa a allowlist
ao lado — inclusive para exfiltração de dados.

Detalhe que tornava a remoção arriscada: **`https://api.easyhealth.art` não estava na
`connect-src`**. O browser fala com a API cross-origin (`src/shared/lib/api.ts`), e isso
só funcionava por causa do curinga. Remover o `https:` sem adicionar o host derrubaria o
app inteiro.

A lista nova é montada a partir dos destinos realmente usados: origem da API (derivada de
`NEXT_PUBLIC_API_URL`, com fallback para o literal de produção), GA4 (incluindo endpoints
regionais), GTM, Google Ads/DoubleClick, Sentry, Clarity e o beacon do Cloudflare Web
Analytics. Não há upload direto para S3 no client, nem WebSocket/EventSource, nem chamada
a Stripe pelo browser — o billing redireciona para URL gerada no servidor.

Também foram adicionadas **`base-uri 'self'`** e **`form-action 'self'`**, ambas ausentes.

---

### [MEDIUM] Certificado TLS expira em 40 dias

**Status:** monitorado por workflow agendado e por check pós-deploy.

O certificado público observado em 2026-07-05 expira em **2026-08-14 23:09:20 GMT** para `easyhealth.art` e `api.easyhealth.art`. Em 2026-08-18 o certificado vigente é o renovado automaticamente pela Cloudflare, com `notAfter` **2026-10-12 22:36:05 GMT**.

**Implementado:**

- `scripts/check_cert_expiry.sh` verifica um ou mais domínios e falha quando restam menos dias que o limite configurado.
- `.github/workflows/tls-certificate-check.yml` roda diariamente às 08:15 UTC e também aceita `workflow_dispatch`.
- `.github/workflows/deploy.yml` mantém o aviso pós-deploy, sem bloquear deploy por causa de expiração próxima.

```yaml
# .github/workflows/tls-certificate-check.yml
on:
  schedule:
    - cron: "15 8 * * *"
  workflow_dispatch:

run: bash scripts/check_cert_expiry.sh easyhealth.art "$WARN_DAYS" api.easyhealth.art
```

> Cloudflare Universal SSL renova certificados de borda automaticamente para domínios ativos, mas o alerta recorrente continua necessário para detectar falhas operacionais antes da expiração: https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/

---

### [LOW] Sem correlation id visível na resposta

**Status:** corrigido.

**API Rails:** já retorna `X-Request-Id` via `ApplicationController#set_request_id_header` e usa `config.log_tags = [ :request_id ]` em produção.

**Web Next.js:** `web/src/proxy.ts` agora gera um UUID por request, retorna headers seguros ao cliente e propaga o request id para o render upstream do Next. Como o projeto usa `src/app`, o Proxy precisa ficar dentro de `src/` para ser carregado pelo Next.

Headers públicos esperados no web:

```http
X-Request-Id: <uuid>
X-Correlation-Id: <mesmo uuid>
```

Nenhum contrato JSON, cookie de sessão, autenticação ou fluxo Rails foi alterado.

---

## ⚠️ Residual Aceito

### [LOW] Header `Server` expõe software do servidor

**Status:** residual operacional aceito na borda Cloudflare.

O código da aplicação já reduz exposição onde controla a resposta:

- `web/next.config.ts` usa `poweredByHeader: false`.
- `api/config/initializers/security_headers.rb` remove `Server` e `X-Powered-By` quando esses headers são adicionados pela aplicação/origem.

O header público observado é:

```http
server: cloudflare
```

Esse header vem do edge da Cloudflare. A documentação de Response Header Transform Rules informa que certos headers, incluindo `server`, não podem ser modificados por essa funcionalidade. Portanto, não há correção confiável em Rails/Next para remover esse valor público enquanto o tráfego estiver atrás da Cloudflare.

Referência: https://developers.cloudflare.com/rules/transform/response-header-modification/

---

## Controles Já Implementados

| Controle | Onde |
|----------|------|
| HSTS | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| Content Security Policy | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| `X-Content-Type-Options: nosniff` | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| `X-Frame-Options: DENY` | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| `Referrer-Policy: strict-origin-when-cross-origin` | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| `Permissions-Policy` | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| `Cross-Origin-Opener-Policy` | `web/next.config.ts` + `api/config/initializers/security_headers.rb` |
| Rate limiting geral | `api/config/initializers/rack_attack.rb` |
| Brute-force no login | `api/config/initializers/rack_attack.rb` |
| Proteção signup spam | `api/config/initializers/rack_attack.rb` |
| `base-uri` e `form-action` | `web/next.config.ts` |
| SAST Rails (Brakeman, bloqueante) | `.github/workflows/pr-check.yml` + `api/config/brakeman.ignore` |
| CVEs em gems (bundler-audit, bloqueante) | `.github/workflows/pr-check.yml` |
| CVEs em npm (`npm audit --audit-level=high`, bloqueante) | `.github/workflows/pr-check.yml` |
| Lint Ruby sobre baseline (RuboCop, bloqueante) | `.github/workflows/pr-check.yml` + `api/.rubocop_todo.yml` |
| Atualização automática de dependências | `.github/dependabot.yml` (bundler, npm, github-actions) |

---

## ⚠️ Risco residual a confirmar no VPS

`docker-compose.prod.yml` publica `3001:3001` (api) e `3000:3000` (web) **sem endereço de
bind**, ou seja, em `0.0.0.0`. Se o firewall do host não bloquear essas portas, a origem é
alcançável direto por IP, **contornando Cloudflare, WAF e o rate limiting por IP** do
`rack-attack`.

Não foi possível determinar a topologia pelos arquivos do repositório: **não há nenhuma
configuração de reverse proxy versionada** (sem nginx, Caddy, Traefik ou cloudflared) e o
deploy roda em runner `self-hosted` no próprio VPS (`.github/workflows/deploy.yml`, em
`/home/easy/Easy-Health`). Por isso **o compose não foi alterado** — trocar para
`127.0.0.1:3000:3000` derrubaria o site caso a Cloudflare alcance os containers
diretamente.

A verificar no servidor, antes de qualquer mudança:

```bash
ss -tlnp | grep -E '3000|3001'      # em que interface cada porta escuta
sudo ufw status verbose             # ou: sudo iptables -S
docker ps --format '{{.Names}}\t{{.Ports}}'
systemctl status nginx caddy cloudflared 2>/dev/null
curl -sI http://<IP_PUBLICO_DO_VPS>:3000/   # deve falhar/timeout se protegido
```

E no painel da Cloudflare: o modo SSL/TLS deve ser **Full (strict)**; `Flexible` deixaria
o tráfego borda→origem em texto claro.

**Relacionado — IP real atrás da Cloudflare.** Não há `trusted_proxies` nem tratamento de
`CF-Connecting-IP` na API (Rails no default). O `req.ip` que o `rack-attack` usa vem do
`X-Forwarded-For`, que é forjável **se** a origem for acessível diretamente. A correção
depende do resultado da verificação acima e **não foi aplicada às cegas**: configurar
`trusted_proxies` errado transforma header enviado pelo cliente em IP confiável, o que é
pior do que o estado atual.

---

## Validação Recomendada

```bash
# API
cd api
bundle exec brakeman --no-pager --ensure-ignore-notes --ensure-no-obsolete-ignore-entries
bundle exec brakeman --show-ignored --no-pager
bundle exec bundler-audit check --update
bundle exec rubocop
bundle exec rspec

# Web
cd ../web
npm audit --audit-level=high
npm run typecheck && npm run lint && npm run build && npm test

# Borda
bash scripts/check_cert_expiry.sh easyhealth.art 45 api.easyhealth.art
curl -I https://easyhealth.art/
curl -I https://api.easyhealth.art/api/v1/health
```

> `rspec` roda **no host**, não no container: `DB_PORT=5433` e `DB_PASSWORD` do `.env`.

Após deploy, `easyhealth.art` deve exibir `x-request-id` e `x-correlation-id`; `api.easyhealth.art` deve continuar exibindo `x-request-id`.

Confirme também que a CSP servida não contém mais o curinga `https:` e que inclui a
origem da API:

```bash
curl -sI https://easyhealth.art/ | tr ';' '\n' | grep -i 'connect-src'
```

---

## Limitações desta rodada

- A CSP foi validada por build e pelo header realmente servido por `next start`, **não**
  por navegação completa no browser em produção. Percorrer home, login, login Google,
  onboarding, geração de plano, execução de treino e telas de analytics conferindo o
  console continua pendente antes do deploy.
- A exposição da origem (seção acima) foi investigada pelo repositório, mas **não
  confirmada no servidor**.
- `web/src/app/(app)/workout/today/warmup-data.ts` referencia `images.unsplash.com`, host
  que **não está** em `img-src` — essas imagens de aquecimento já estão bloqueadas por CSP
  em produção hoje. É um bug pré-existente, não introduzido aqui, e foi deixado como está
  para não misturar mudança funcional nesta rodada de segurança.
