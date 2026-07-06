# Android Internal Testing — Deploy Pipeline

## Visão Geral

O pipeline de deploy Android funciona em dois estágios:

```
push main / workflow_dispatch
        │
        ▼
  [build]  ── automático, sem aprovação
    1. npm ci + npm run build (Next.js)
    2. npx cap sync android
    3. Decodifica keystore do secret ANDROID_KEYSTORE_BASE64
    4. ./gradlew bundleRelease
    5. Salva o .aab como artifact GitHub
        │
        ▼  (needs: build)
  [upload-to-play]  ← PAUSA PARA APROVAÇÃO MANUAL
    environment: internal-testing
    6. Aprova no GitHub → upload para Google Play track: internal
```

O job de build roda automaticamente a cada push na `main`. O upload só acontece após aprovação manual no GitHub Environment `internal-testing`.

---

## Secrets Necessários

### Repository Secrets
(Settings → Secrets and variables → Actions → New repository secret)

| Secret | Descrição |
|--------|-----------|
| `ANDROID_KEYSTORE_BASE64` | Keystore em base64 (ver comando abaixo) |
| `ANDROID_KEYSTORE_PASSWORD` | Senha da keystore |
| `ANDROID_KEY_ALIAS` | Alias da chave de assinatura |
| `ANDROID_KEY_PASSWORD` | Senha da chave de assinatura |
| `GOOGLE_SERVICES_JSON_BASE64` | google-services.json do Firebase Console em base64 (ver web/docs/firebase-push-android.md) |

### Environment Secrets — `internal-testing`
(Settings → Environments → internal-testing → Add secret)

| Secret | Descrição |
|--------|-----------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON completo da Service Account |
| `PLAY_PACKAGE_NAME` | Package name: `com.EasyHealth.myapp` |

---

## Comandos para Gerar Cada Secret Localmente

```bash
# ANDROID_KEYSTORE_BASE64
base64 -w 0 ~/secure/EasyHealth/android/easyhealth-release.jks
# Cole o output completo como valor do secret

# GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
cat ~/secure/EasyHealth/google-play/service-account.json
# Cole o conteúdo JSON completo como valor do secret

# Validar que o JSON da service account é válido
cat ~/secure/EasyHealth/google-play/service-account.json | jq .

# ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD
# Use os mesmos valores que você definiu ao criar a keystore com keytool
# Para verificar o alias:
keytool -list -v -keystore ~/secure/EasyHealth/android/easyhealth-release.jks
```

---

## Como Aprovar o Deploy no GitHub

1. Acesse a aba **Actions** do repositório no GitHub
2. Clique no workflow run que deseja aprovar
3. Na seção **upload-to-play**, clique em **Review deployments**
4. Selecione `internal-testing` e clique em **Approve and deploy**
5. O upload para Google Play Internal Testing será iniciado automaticamente

---

## Como Verificar no Google Play Console

1. Acesse [Google Play Console](https://play.google.com/console)
2. Selecione o app **Easy Health**
3. Navegue até **Testing → Internal Testing**
4. O novo release deve aparecer em alguns minutos após o upload
5. Clique em **Release dashboard** para ver o status do processamento

---

## Build Local (Sem CI)

```bash
# Exportar variáveis de ambiente antes de buildar
export ANDROID_KEYSTORE_PATH=~/secure/EasyHealth/android/easyhealth-release.jks
export ANDROID_KEYSTORE_PASSWORD=sua_senha_aqui
export ANDROID_KEY_ALIAS=seu_alias_aqui
export ANDROID_KEY_PASSWORD=sua_senha_chave_aqui
export ANDROID_VERSION_CODE=1
export ANDROID_VERSION_NAME="1.0.0"

# Build completo
cd ~/projects/Easy-Health/web
npm ci
npm run build
npx cap sync android
cd android
./gradlew bundleRelease

# Verificar o .aab gerado
ls -lh app/build/outputs/bundle/release/app-release.aab
```

---

## Rollback / Reenvio de Build

**Para reenviar uma build anterior:**
1. No GitHub Actions, encontre o workflow run desejado
2. Clique em **Re-run jobs → Re-run failed jobs** (ou **Re-run all jobs**)
3. Aguarde o build e aprove o upload novamente

**Para fazer rollback no Google Play:**
1. No Google Play Console → Internal Testing
2. Acesse o release anterior e clique em **Promote to production** (se promovido)
3. Ou crie um novo release manualmente no Console com um `.aab` anterior

**Nota**: No track `internal`, todos os releases coexistem e testadores podem optar por qualquer versão disponível.

---

## AVISO CRÍTICO — Segurança dos Arquivos

Os arquivos abaixo são **insubstituíveis**. Se perdidos, será necessário criar nova keystore e novo app no Play Console.

```
~/secure/EasyHealth/android/easyhealth-release.jks    ← KEYSTORE DE ASSINATURA
~/secure/EasyHealth/google-play/service-account.json  ← SERVICE ACCOUNT GOOGLE PLAY
```

**Recomendações:**
- Faça backup em local seguro e offline (ex: pen drive criptografado)
- Nunca commite esses arquivos no repositório
- Nunca compartilhe por e-mail ou chat
- Armazene a senha da keystore em um gerenciador de senhas (ex: Bitwarden, 1Password)

---

## Service Account configurada

- **Email**: `github-easyhealth-play@neat-element-485812-q2.iam.gserviceaccount.com`
- **Permissões necessárias no Play Console**: Release Manager (ou superior) para o app
- **Projeto GCP**: `neat-element-485812-q2`
