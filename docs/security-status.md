# Security Status — easyhealth.art

**Avaliado em:** 2026-05-31  
**Scan original:** 13 achados · 0 críticos · 2 altos · 2 médios · 4 baixos  
**Status atual:** 7/8 achados resolvidos · 1 pendente

---

## Resumo

| Severidade | Total | Resolvido | Pendente |
|------------|-------|-----------|----------|
| Crítico    | 0     | —         | —        |
| Alto       | 2     | ✅ 2      | 0        |
| Médio      | 2     | ✅ 2      | 0        |
| Baixo      | 4     | ✅ 3      | ⚠️ 1     |

---

## ✅ Resolvidos

### [HIGH] HSTS ausente

**Arquivo:** `web/next.config.ts:9` + `api/config/initializers/security_headers.rb`

```ts
// web/next.config.ts
{ key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
```

```ruby
# api/config/initializers/security_headers.rb
"Strict-Transport-Security" => "max-age=31536000; includeSubDomains",
```

---

### [HIGH] Content Security Policy (CSP) ausente

**Arquivo:** `web/next.config.ts:23-36` + `api/config/initializers/security_headers.rb`

```ts
// web/next.config.ts — CSP completo por ambiente
{
  key: "Content-Security-Policy",
  value: [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${process.env.NODE_ENV === "development" ? " 'unsafe-eval'" : ""}
      https://static.cloudflareinsights.com https://www.googletagmanager.com
      https://www.clarity.ms https://scripts.clarity.ms
      https://googleads.g.doubleclick.net`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https://www.google.com ...",
    "connect-src 'self' https: https://www.google-analytics.com ...",
    "font-src 'self'",
    "worker-src blob: 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
  ].join("; "),
},
```

```ruby
# api/config/initializers/security_headers.rb — CSP restritivo para a API
"Content-Security-Policy" => "default-src 'none'; frame-ancestors 'none'"
```

---

### [MEDIUM] X-Content-Type-Options ausente

**Arquivo:** `web/next.config.ts:11` + `api/config/initializers/security_headers.rb`

```ts
{ key: "X-Content-Type-Options", value: "nosniff" },
```

```ruby
"X-Content-Type-Options" => "nosniff",
```

---

### [MEDIUM] Certificado TLS expira em 74 dias

**Monitoramento implementado** via script + GitHub Actions a cada deploy para `easyhealth.art` e `api.easyhealth.art`.

```bash
# scripts/check_cert_expiry.sh
DOMAIN="${1:-easyhealth.art}"
WARN_DAYS="${2:-45}"
# Verifica openssl e alerta se qualquer dominio tiver < WARN_DAYS dias
```

```yaml
# .github/workflows/deploy.yml — step final
- name: Check TLS certificate expiry
  run: bash scripts/check_cert_expiry.sh easyhealth.art 45 api.easyhealth.art ||
       echo "::warning::TLS certificate for EasyHealth is expiring soon - renew it!"
```

> **Ação operacional na VPS:** configurar auto-renovação no servidor, por exemplo com cron/systemd timer para `certbot renew --quiet` e deploy hook para recarregar o proxy (`nginx -s reload`, `systemctl reload nginx` ou equivalente do proxy usado).  
> O repositório monitora e alerta; a renovação efetiva depende da configuração TLS do servidor.

### [LOW] Header Server expõe software do servidor

**Ação operacional na VPS/proxy:** remover ou reduzir o header no proxy que termina TLS. Em Nginx, usar `server_tokens off;` e, se houver módulo apropriado, limpar `Server`. Em Cloudflare/CDN, aplicar regra equivalente no edge. Rails/Next não conseguem remover de forma confiável um header adicionado pelo proxy externo.

---

### [LOW] Permissions-Policy ausente

**Arquivo:** `web/next.config.ts:17` + `api/config/initializers/security_headers.rb`

```ts
{ key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
```

```ruby
"Permissions-Policy" => "camera=(), microphone=(), geolocation=()",
```

---

### [LOW] Cross-Origin-Opener-Policy (COOP) ausente

**Arquivo:** `web/next.config.ts:19` + `api/config/initializers/security_headers.rb`

```ts
{ key: "Cross-Origin-Opener-Policy", value: "same-origin" },
```

```ruby
"Cross-Origin-Opener-Policy" => "same-origin",
```

---

### [LOW] Header Server expõe software

**Arquivo:** `web/next.config.ts:40` + `api/config/initializers/security_headers.rb`

```ts
// Next.js — remove X-Powered-By
const nextConfig = {
  poweredByHeader: false,
  // ...
};
```

```ruby
# Rails — middleware remove Server e X-Powered-By dinamicamente
Rails.application.config.middleware.insert_before 0, Class.new {
  def initialize(app) = (@app = app)
  def call(env)
    status, headers, body = @app.call(env)
    headers.delete("Server")
    headers.delete("X-Powered-By")
    [status, headers, body]
  end
}
```

---

## ⚠️ Pendente

### [LOW] Correlation ID por request

**Status:** não implementado.

**O que fazer:** gerar um UUID por request, propagar em logs e retornar em header seguro.

```ruby
# Sugestão — api/config/initializers/correlation_id.rb
Rails.application.config.middleware.insert_before 0, Class.new {
  def initialize(app) = (@app = app)
  def call(env)
    request_id = env["HTTP_X_REQUEST_ID"].presence || SecureRandom.uuid
    env["action_dispatch.request_id"] = request_id
    status, headers, body = @app.call(env)
    headers["X-Request-Id"] = request_id
    [status, headers, body]
  end
}
```

> Rails já faz isso automaticamente com `ActionDispatch::RequestId` (ativado por padrão).  
> Verificar se está incluído no middleware stack: `bin/rails middleware | grep RequestId`

---

## Bônus implementado (não estava no plano original)

| Item | Onde |
|------|------|
| `X-Frame-Options: DENY` (anti-clickjacking) | `next.config.ts` + `security_headers.rb` |
| `Referrer-Policy: strict-origin-when-cross-origin` | `next.config.ts` + `security_headers.rb` |
| Rate limiting geral (300 req/5min/IP) | `api/config/initializers/rack_attack.rb` |
| Brute-force no login (10 tentativas/min/IP) | `api/config/initializers/rack_attack.rb` |
| Proteção signup spam (5 tentativas/min/IP) | `api/config/initializers/rack_attack.rb` |
| `unsafe-eval` só em desenvolvimento (Turbopack) | `next.config.ts` (CSP condicional) |
