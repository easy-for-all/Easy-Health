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

RUN npm run build

EXPOSE 3000

CMD ["npm", "start"]
