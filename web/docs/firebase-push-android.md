# Firebase Push Notifications — Android Setup

## Package name do app

```
com.EasyHealth.myapp
```

---

## 1. Criar/configurar projeto no Firebase

1. Acesse [https://console.firebase.google.com](https://console.firebase.google.com)
2. Crie ou selecione o projeto **EasyHealth**
3. **Project Settings** → **Your apps** → botão **Add app** → **Android**
   - Android package name: `com.EasyHealth.myapp`
   - App nickname: `EasyHealth Android`
4. Clique em **Register app**
5. Baixe o arquivo `google-services.json`
6. Clique em **Next** até concluir o wizard

---

## 2. Adicionar SHA-1 e SHA-256 (necessário para Google Sign-In via Firebase)

### Keystore de release (`~/.android/easyhealth-release.keystore`)

```bash
keytool -list -v \
  -keystore ~/.android/easyhealth-release.keystore \
  -alias easyhealth \
  -storepass SUA_SENHA
```

### Keystore de debug (`~/.android/debug.keystore`)

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android
```

Copie os valores de **SHA-1** e **SHA-256** e adicione em:
**Firebase Console → Project Settings → Your apps → Android app → Add fingerprint**

---

## 3. Desenvolvimento local

Coloque `google-services.json` em:

```
web/android/app/google-services.json
```

> Este arquivo está no `.gitignore` — nunca commite.

Se a pasta `android/` não existir ainda, rode:

```bash
cd web
npx cap add android
cp android-config/app-build.gradle android/app/build.gradle
```

Depois coloque o arquivo e rode o build:

```bash
./build-android-local.sh
```

O script valida a presença do arquivo antes de compilar.

---

## 4. CI/CD (GitHub Actions)

Adicione um secret no repositório:

| Nome do secret | Valor |
|---|---|
| `GOOGLE_SERVICES_JSON_BASE64` | Conteúdo base64 do `google-services.json` |

Para gerar o valor:

```bash
base64 -w0 google-services.json
```

O workflow `.github/workflows/android-internal-testing.yml` decodifica automaticamente o secret e escreve o arquivo em `web/android/app/google-services.json` antes do `cap sync`.

---

## 5. Habilitar Cloud Messaging

No Firebase Console:
- **Project Settings** → aba **Cloud Messaging**
- Verifique que FCM está ativo (é habilitado por padrão)
- Anote a **Server key** se precisar enviar notificações via API diretamente

---

## 6. Testar push notifications

### Build debug e instalar

```bash
cd web/android
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

### Fluxo de teste

1. Abra o app e faça login
2. Aceite a permissão de notificação quando solicitado
3. No Logcat, filtre por `[Push]` — você verá o token FCM gerado
4. No banco de dados, confirme: `SELECT * FROM device_tokens;`
5. No Firebase Console → **Cloud Messaging** → **Send test message**:
   - Target: **Single device**
   - Cole o token FCM do Logcat
6. A notificação deve aparecer no dispositivo

### Verificar no backend (Rails logs)

```
POST /api/v1/device_tokens 200
```

---

## 7. Permissões Android (automáticas)

O plugin `@capacitor/push-notifications` adiciona automaticamente via `cap sync`:
- `POST_NOTIFICATIONS` — Android 13+ (API 33+), exige dialog de permissão
- `RECEIVE_BOOT_COMPLETED` — para notificações agendadas

Nenhuma edição manual do `AndroidManifest.xml` é necessária.

---

## Arquivos relevantes

| Arquivo | Propósito |
|---|---|
| `web/capacitor.config.ts` | Config do plugin PushNotifications |
| `web/src/shared/lib/pushNotifications.ts` | Serviço de init/registro |
| `web/src/features/auth/auth-context.tsx` | Ponto de integração (após login) |
| `api/app/controllers/api/v1/device_tokens_controller.rb` | Endpoint de registro de token |
| `api/db/migrate/20260701000001_create_device_tokens.rb` | Migration da tabela |
| `.github/workflows/android-internal-testing.yml` | CI/CD com decode do secret |
