# iOS — bundle local e autenticação nativa

Estado: PR 0 (0A + 0B) concluído no código. **Nada foi executado em simulador ou
device** — o ambiente de desenvolvimento é Linux/WSL.

## Por que bundle local, e não `server.url`

O Android roda como shell de WebView remoto: `capacitor.config.ts` aponta
`server.url` para `https://easyhealth.art` e o app baixa a aplicação inteira a
cada abertura. Funciona no Google Play.

No iOS isso não passa. Duas guidelines batem no mesmo ponto:

- **2.5.2** — o app não pode baixar e executar código que não estava no bundle.
- **4.2** — site empacotado é rejeitado por funcionalidade mínima.

Então o IPA embarca os assets. `server.url` no target iOS existe **apenas** para
live reload em desenvolvimento, via `CAP_LIVE_RELOAD_URL`, e há um teste que
falha o build se ele vazar para o release.

O Rails continua remoto. O que muda é de onde vem o HTML/JS/CSS, não de onde
vêm os dados.

```
IPA
 ├─ index.html      (local)
 ├─ assets/*.js     (local)
 ├─ assets/*.css    (local)
 └─ ícones/imagens  (local)
          │
          ▼
   https://api.easyhealth.art   ← Rails, remoto, fonte autoritativa
```

## Como o bundle é construído

```bash
npm run build:web      # next build — Web e Android, inalterado
npm run build:native   # vite build --config vite.native.config.ts → web/out-native/
```

`out-native/` é o `webDir` do target iOS. `web/ios/` e `web/out-native/` são
gerados e não versionados, mesma regra de `web/android/`.

### Por que Vite e não `next build`

`output: "export"` exige `generateStaticParams` com conjunto fechado para cada
segmento dinâmico. O app tem seis segmentos de id não limitado — `/users/[id]`,
`/community/[id]`, `/personal/clients/[id]`, `/personal/students/[id]`,
`/s/[token]`, `/join/[code]`. Não existe conjunto fechado, e inventar ids seria
mentira: `/users/1` e `/users/2` não podem virar arquivos HTML dentro do IPA.

A auditoria mostrou que isso não é um problema real, porque a superfície do app
já é uma SPA: `src/app/(app)/**` é 100% client components, não há route
handlers, existe um único Server Action (troca de locale) e todo o data fetching
já sai cross-origin para o Rails.

### O que evita duplicar o produto

Três aliases em `vite.native.config.ts`:

| import | vira |
|---|---|
| `next/navigation` | `src/native/adapters/navigation.ts` |
| `next/link` | `src/native/adapters/link.tsx` |
| `next/image` | `src/native/adapters/image.tsx` |

Os 51 arquivos que importam `next/navigation` e os 49 que importam `next/link`
**não mudaram**. Sem os aliases, seria preciso reescrever a navegação inteira do
produto para introduzir uma segunda árvore de rotas.

`src/native/routes.tsx` importa os mesmos `page.tsx` que o Next renderiza. Nada
foi copiado: cada tela continua tendo uma única implementação.

## Roteamento

`src/native/router/` — roteador client-side escrito à mão (~200 linhas), sem
dependência nova. A superfície que os adapters precisam cobrir é pequena:
push/replace/back/pathname/searchParams/params.

**A tabela de rotas é a allowlist.** Uma rota não registrada não navega, mesmo
que o caminho pareça inofensivo. Rota vinda de fora (deep link, push, URL
preservada pelo WebView) passa por `resolveExternalRoute`, que reusa
`isSafeInternalPath` de `push-deep-link.ts` e descarta host que não seja
`easyhealth.art`. Fallback é `/`.

### Adapter de navegação

`src/shared/lib/app-navigation.ts` desacopla navegação interna do documento.
Na Web, `navigateInternal` cai em `window.location`; no shell nativo, o
`NavigationBridge` registra o roteador. Sem isso,
`window.location.replace("/login")` em `auth-context.tsx` pediria um documento
que não existe dentro do IPA.

`navigateExternal` (checkout Stripe, OAuth Google) **nunca** é interceptada — o
destino não é rota nossa.

## MobileSession

### O problema

A sessão do Devise é cookie `SameSite=Lax`. Com bundle local a origem passa a
ser `capacitor://localhost`, e requisições para `api.easyhealth.art` viram
cross-site — o cookie não viaja. `SameSite=None` não resolveria: o WKWebView
bloqueia cookie de terceiros por ITP, e afrouxar o cookie penalizaria
Web/Android por um problema que é só do iOS.

CSRF não entra na conta: o Rails está `api_only`, sem `protect_from_forgery`.

### A solução

Token opaco `ehs_<random>`, digest SHA-256 em repouso, revogável. Espelha
`MobileAuthCode`, que já existia no projeto.

Opaco e não JWT de propósito: o valor está em revogar imediatamente no logout,
na exclusão de conta e por ação administrativa. Um token auto-descritivo só
consegue isso com uma lista de revogação — que é esta tabela.

| Etapa | Onde |
|---|---|
| Emissão | login/signup/google-native/mobile-exchange, sob opt-in `X-EasyHealth-Mobile-Session` |
| Transporte | `Authorization: Bearer ehs_...`, injetado centralmente em `api.ts` |
| Autenticação | `MobileSessionAuthentication`, antes do `authenticate_user!` |
| Armazenamento | Keychain (iOS) |
| Expiração | 90 dias, via `MOBILE_SESSION_TTL_DAYS` |
| Revogação | logout, exclusão de conta, rotação por device |

**Emissão é opt-in.** Sem o header, o servidor não emite nada — o bundle web
nunca recebe bearer token exposto a XSS sem ter utilidade, porque lá o cookie
httponly já resolve.

**O prefixo `ehs_` não é decoração.** `AnonymousAuthentication` e os controllers
de integração do Make também leem `Authorization: Bearer` no mesmo nível. Sem o
guard de prefixo, um token anônimo válido receberia 401 antes de chegar no
concern que sabe lê-lo.

### Rotação

Reautenticar **no mesmo aparelho** substitui a sessão anterior daquele
`installation_id` (`revocation_reason: "superseded"`). Reautenticar **não**
derruba os outros aparelhos: entrar no iPhone não pode deslogar o iPad. Sem
`installation_id`, cai num teto de 10 sessões ativas por usuário, mantendo as
mais recentes.

### Bootstrap: 401 ≠ offline

```
launch → lê Keychain → sem token  → não autenticado
                     → com token  → GET /api/v1/auth/me
                                     ├─ 200 → autenticado
                                     ├─ 401/403 → apaga o token → login
                                     └─ rede/5xx → MANTÉM o token
```

Apagar o token numa falha de rede deslogaria o usuário toda vez que o metrô
entrasse num túnel. Coberto por spec.

### Logout

Revoga no servidor, depois limpa o Keychain e o estado em memória. Se o backend
estiver indisponível, o token local é removido do mesmo jeito e o usuário volta
para a tela de login — nunca fica aparentemente logado. A sessão remota
sobrevivente expira sozinha em até 90 dias; não foi criada fila de retry porque
o custo de uma sessão órfã de leitura é menor que o de uma fila persistente.

## Keychain — política de acessibilidade

`web/native-plugins/easyhealth-secure-storage/`, plugin nativo local. Sem SaaS,
sem dependência enterprise.

```
kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

| Escolha | Por quê |
|---|---|
| `ThisDeviceOnly` | Não entra no iCloud Keychain. Uma sessão identifica **um aparelho**; propagá-la para o iPad criaria uma sessão que o servidor nunca emitiu e que ninguém revoga individualmente. Também impede restaurar de backup em outro device. |
| `AfterFirstUnlock` | Legível após o primeiro desbloqueio pós-boot, inclusive com a tela apagada. `WhenUnlocked` quebraria trabalho em background. |
| Sem variante biométrica | Face ID a cada leitura é inaceitável para um header que vai em toda requisição. |
| Sem `kSecAttrAccessGroup` | Sem Keychain Sharing: nenhum outro app enxerga o item. |

**Proibido persistir o token em** localStorage, sessionStorage, IndexedDB,
Capacitor Preferences, cookie legível por JS ou arquivo em texto puro. A camada
`nativeSessionStorage` **não tem fallback** para nenhum deles — um fallback
daria a impressão de que a credencial está protegida quando não está. Há spec
verificando que nada com prefixo `ehs_` chega em web storage.

O token nunca vai para log, Sentry, analytics, query string, URL ou deep link.

## CORS

Bloco separado, **aditivo**, em `api/config/initializers/cors.rb`:

```
capacitor://localhost   (iOS)
ionic://localhost       (esquema legado do Capacitor)
http://localhost        (Android com bundle local, futuro)
```

com **`credentials: false`**. Essa é a decisão central: o caminho nativo
autentica por header, nunca por cookie, e marcar `false` é o que impede uma
origem local de passar a carregar a sessão de cookie do domínio principal.

O bloco de origens configuradas (`CORS_ORIGINS`) segue intocado com
`credentials: true`. Nada foi afrouxado globalmente, e nenhuma origem recebe
`*`. Coberto por `spec/requests/cors_spec.rb`, incluindo o caso do lookalike
`capacitor://localhost.evil.com`.

## Schema — estado e reconciliação

O PR 0 deveria produzir **apenas** isto em `api/db/schema.rb`:

- bump de versão para `2026_08_18_120000`
- a tabela `mobile_sessions` e seus quatro índices

O `schema.rb` da árvore de trabalho contém **também** colunas de
`health_profiles` (`scheduled_workout_reminder_suppressed_at`,
`scheduled_workout_reminder_suppression_metadata`,
`scheduled_workout_reminder_suppression_reason` + índice parcial), vindas da
migration `20260816120000_add_scheduled_workout_reminder_suppression_to_health_profiles.rb`,
que **não está commitada** e não pertence a este PR.

Por isso `api/db/schema.rb` foi deixado **fora** dos commits do PR 0.

Reconciliar assim que a migration de scheduled reminders for commitada:

```bash
# com a branch de scheduled reminders já mergeada
cd api
DB_PORT=5433 RAILS_ENV=test bundle exec rails db:migrate
git add db/schema.rb    # agora o diff contém as duas migrations, ambas commitadas
```

Enquanto isso não acontecer, o job `migrations` do CI vai falhar em
`git diff --exit-code db/schema.rb`, porque a migration `20260818120000` está
commitada e a entrada correspondente não. **Não editar a migration alheia para
deixar o CI verde.**

## Fluxo no macOS

```bash
cd web
npm install
npm run build:native
npm run ios:setup     # cap add ios --packagemanager SPM + cap sync, com guarda de server.url
npm run ios:open
```

No Xcode: Team → Bundle Identifier → Signing & Capabilities → device → Run.

## Fora do escopo do PR 0

StoreKit, AppleSubscription, JWS, App Store Server API, webhooks, Sign in with
Apple, APNs, Firebase Messaging iOS, Universal Links definitivos e CI de
TestFlight. Todos nos PRs 1–6.
