# Security Status — easyhealth.art

**Avaliado em:** 2026-07-05  
**Scan mais recente:** 2026-07-04 · 11 achados · 0 críticos · 0 altos · 1 médio · 2 baixos  
**Status atual:** achados médios e baixos tratados no código/monitoramento, com 1 residual operacional aceito

---

## Resumo

| Achado | Severidade | Status |
|--------|------------|--------|
| Certificado TLS expira em 40 dias | Médio | ✅ Monitoramento recorrente configurado |
| Sem correlation id visível na resposta | Baixo | ✅ Corrigido no web e já existente na API |
| Header `Server` expõe software do servidor | Baixo | ⚠️ Residual Cloudflare aceito/documentado |

---

## ✅ Tratados

### [MEDIUM] Certificado TLS expira em 40 dias

**Status:** monitorado por workflow agendado e por check pós-deploy.

O certificado público observado em 2026-07-05 expira em **2026-08-14 23:09:20 GMT** para `easyhealth.art` e `api.easyhealth.art`.

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

---

## Validação Recomendada

```bash
npm run typecheck
npm run lint
npm run build
bash scripts/check_cert_expiry.sh easyhealth.art 45 api.easyhealth.art
curl -I https://easyhealth.art/
curl -I https://api.easyhealth.art/api/v1/health
```

Após deploy, `easyhealth.art` deve exibir `x-request-id` e `x-correlation-id`; `api.easyhealth.art` deve continuar exibindo `x-request-id`.
