FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

ARG GIT_COMMIT=unknown
COPY . .

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

ARG NEXT_INTERNAL_API_URL=http://api:3001
ENV NEXT_INTERNAL_API_URL=${NEXT_INTERNAL_API_URL}

ARG NEXT_PUBLIC_SENTRY_DSN
ENV NEXT_PUBLIC_SENTRY_DSN=${NEXT_PUBLIC_SENTRY_DSN}

ARG NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID
ENV NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID=${NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID}

# Fail fast: an empty value here would be inlined into the client bundle and the
# native Google Sign-In would throw missing_web_client_id at runtime. Never print
# the value.
RUN test -n "$NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID" \
  || (echo "ERROR: NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID is empty at build time — bundle would ship without Google web client id" && exit 1)

# A/B do fim do onboarding Android. Precisa ser ARG e não só env do container:
# NEXT_PUBLIC_* é inlined no BUILD, então uma variável passada apenas no runtime
# nunca chega ao bundle e a flag ficaria presa no default para sempre.
# Todas default-OFF/ausentes: sem elas o app entrega o fluxo atual.
ARG NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED
ENV NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED=${NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED}

ARG NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD
ENV NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD=${NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD}

ARG NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT
ENV NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT=${NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT}

# Firebase Analytics do app Android (WebView carrega este bundle). Mesma regra do
# bloco acima: NEXT_PUBLIC_* é inlined no BUILD, então uma variável só de runtime
# nunca chega ao bundle. Foi exatamente essa a falha — sem o ARG, firebase.ts
# resolvia FIREBASE_ANALYTICS_ENABLED=false e nenhum evento customizado saía.
# Default true para o caminho de produção nascer correto; `false` explícito no
# .env do servidor segue funcionando como kill switch.
ARG NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED=true
ENV NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED=${NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED}

# Crashlytics do app Android. Faltava ARG/ENV aqui, então firebase.ts resolvia
# FIREBASE_CRASHLYTICS_ENABLED=false em TODO bundle Docker, independente do .env
# do servidor — a mesma classe de falha do bloco acima. Isto controla só o bridge
# JS (setEnabled/setUserId/recordException); a coleta nativa de crashes e ANRs vem
# do plugin Capacitor + plugin Gradle e não depende desta flag.
# Default false: torna a configuração explícita sem ligar coleta silenciosamente.
# Produção liga com NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED=true no .env.
ARG NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED=false
ENV NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED=${NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED}

RUN case "$NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED" in \
      true)  echo "Firebase Crashlytics (bridge JS): LIGADO neste build" ;; \
      false) echo "Firebase Crashlytics (bridge JS): desligado neste build" ;; \
      *) echo "ERROR: NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED='$NEXT_PUBLIC_FIREBASE_CRASHLYTICS_ENABLED' (esperado 'true' ou 'false')" && exit 1 ;; \
    esac

# Só "true" ou "false". Um vazio ou um "True"/"1" resolveriam silenciosamente
# para desligado, que é a falha que este guard existe para tornar impossível.
RUN case "$NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED" in \
      true)  echo "Firebase Analytics (Android): LIGADO neste build" ;; \
      false) echo "WARNING: Firebase Analytics (Android) DESLIGADO por kill switch explicito" ;; \
      *) echo "ERROR: NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED='$NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED' (esperado 'true' ou 'false')" && exit 1 ;; \
    esac

# O contexto de build é ./web e não há .dockerignore, então um .next do host viria
# junto no COPY acima. O build do Next hoje limpa esse diretório, mas o guard
# abaixo audita arquivos: um chunk antigo sobrevivente seria lido como veredito
# sobre um build que não é este.
RUN rm -rf .next

RUN npm run build

# Prova de que o valor foi inlinado. Quando a variável existe no build, o Turbopack
# substitui a leitura pelo literal e o acesso some do chunk; quando não existe, ela
# sobra como leitura de env em runtime — o sintoma exato do incidente.
#
# Em node, não em grep: o grep do Alpine é o do busybox, que não tem --include e
# sai com erro de uso. Dentro de um `if`, esse erro vira "não encontrou nada" e o
# guard passa sempre — foi o que aconteceu na primeira versão deste arquivo.
#
# Casa `.env.` e não `process.env.`: o Turbopack reescreve process para um shim
# (`t.default.env.X`), então procurar por "process.env" daria falso negativo.
RUN node -e ' \
const fs = require("fs"), path = require("path"); \
const FLAG = "NEXT_PUBLIC_FIREBASE_ANALYTICS_ENABLED"; \
const NEEDLES = [".env." + FLAG, ".env[\"" + FLAG + "\"]"]; \
const dir = ".next/static/chunks"; \
const unresolved = []; let scanned = 0; \
(function walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { \
  const f = path.join(d, e.name); \
  if (e.isDirectory()) walk(f); \
  else if (e.name.endsWith(".js")) { \
    scanned++; \
    const src = fs.readFileSync(f, "utf8"); \
    if (NEEDLES.some(function (n) { return src.indexOf(n) !== -1; })) unresolved.push(f); \
  } \
} })(dir); \
if (scanned === 0) { console.error("ERROR: nenhum chunk .js encontrado em " + dir + " — guard nao auditou nada"); process.exit(1); } \
if (unresolved.length) { console.error("ERROR: " + FLAG + " sobrou como leitura de env em " + unresolved.length + " chunk(s): " + unresolved.slice(0, 5).join(", ")); process.exit(1); } \
console.log("OK: " + FLAG + " inlinada; " + scanned + " chunks auditados"); \
'

EXPOSE 3000

CMD ["npm", "start"]
