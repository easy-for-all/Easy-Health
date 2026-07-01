# Android Dev Flow — EasyHealth

## Arquitetura

O app Android é um **WebView wrapper** gerado pelo Capacitor. A WebView carrega
`https://easyhealth.art` (produção). O código nativo em `android/` é 100%
gerado — nunca editado manualmente.

```
web/
├── android/               ← gerado localmente, não versionado (.gitignore)
├── android-config/        ← configurações customizadas, versionadas
│   ├── app-build.gradle
│   └── gradle/wrapper/gradle-wrapper.properties
├── scripts/
│   └── setup-android.sh   ← setup idempotente
└── build-android-local.sh ← build AAB release local
```

---

## Pré-requisitos

| Ferramenta | Versão mínima | Instalação |
|---|---|---|
| Android Studio | Ladybug (2024.2+) | developer.android.com/studio |
| JDK | 21 (Temurin) | `sudo apt install openjdk-21-jdk` ou sdkman |
| Node.js | 20+ | já instalado no projeto |
| ANDROID_HOME | — | configurar após instalar Android Studio |

### Configurar ANDROID_HOME no WSL

Adicione ao `~/.bashrc` (ou `~/.zshrc`):

```bash
export ANDROID_HOME="$HOME/Android/Sdk"         # caminho padrão do Linux
# OU, se o SDK está no Windows:
# export ANDROID_HOME="/mnt/c/Users/SEU_USUARIO/AppData/Local/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
```

---

## Setup inicial (primeira vez ou após clone)

```bash
cd ~/projects/Easy-Health/web
npm install           # instala dependências (já feito normalmente)
npm run android:setup # regenera android/, aplica configs e sincroniza
```

O script `setup-android.sh` é **idempotente**: se `android/gradlew` já existir,
ele só aplica configs e sincroniza sem recriar a pasta.

---

## Abrir no Android Studio

```bash
npm run android:open
```

Ou manualmente:
1. Abrir Android Studio
2. **File → Open**
3. Navegar até `Easy-Health/web/android` e clicar **OK**
4. Aguardar o Gradle sync (primeira vez baixa dependências — pode demorar)
5. O módulo **app** deve aparecer na árvore de projetos

> **Dica WSL**: Se o Android Studio está instalado no Windows, abra a pasta
> `C:\Users\SEU_USUARIO\...\Easy-Health\web\android` diretamente pelo Windows Explorer
> clicando com botão direito → "Open in Android Studio".

---

## Criar emulador com Google Play

Para testar login Google, o emulador precisa de **Google Play APIs**.

1. Android Studio → **Tools → Device Manager**
2. Clique **+** → **Create Virtual Device**
3. Escolha hardware: **Pixel 8** (ou similar)
4. Escolha imagem de sistema: aba **Google Play** → **API 34** (ou maior)
5. Finalize e inicie o emulador

> Imagens com "Google Play" (não "Google APIs") permitem instalar apps da Play
> Store e são necessárias para login Google funcionar corretamente.

---

## Rodar o app no emulador

1. Inicie o emulador (Device Manager → play ▶)
2. No Android Studio, clique em **Run 'app'** (▶) na barra superior
3. Selecione o emulador na lista de destinos
4. O app abre como WebView carregando `https://easyhealth.art`

---

## Abrir Logcat

**View → Tool Windows → Logcat**

Filtros úteis:
- `Capacitor` — logs do bridge nativo/web
- `GoogleSignIn` ou `Auth` — logs de autenticação
- `WebView` — erros do Chrome WebView

---

## Debug da WebView com chrome://inspect

Permite inspecionar o DOM e o console JavaScript da WebView dentro do emulador.

1. Instale um build **debug** no emulador:
   ```bash
   cd ~/projects/Easy-Health/web
   npm run android:build:debug
   # instalar o APK no emulador:
   adb install android/app/build/outputs/apk/debug/app-debug.apk
   ```
2. Abra o Chrome no desktop (Windows ou Linux com GUI)
3. Acesse `chrome://inspect/#devices`
4. O emulador aparece como dispositivo; clique **inspect** abaixo da WebView
5. DevTools abre com acesso completo ao console, network e DOM

---

## Gerar AAB

### Build local (WSL)

```bash
cd ~/projects/Easy-Health/web
npm run android:build:aab
```

O script `build-android-local.sh`:
1. Instala Android SDK se necessário (`~/android-sdk/`)
2. Lê keystore de `~/.android/easyhealth-release.keystore`
3. Roda `setup-android.sh` (garante android/ completo)
4. Executa `./gradlew bundleRelease`
5. Copia o AAB para `../releases/app-release-TIMESTAMP.aab`

Para sobrescrever as credenciais sem editar o script:

```bash
export ANDROID_KEYSTORE_PASSWORD="sua-senha"
export ANDROID_KEY_PASSWORD="sua-senha"
npm run android:build:aab
```

### Build via CI (GitHub Actions)

Disparado automaticamente em push para `main` via `.github/workflows/android-internal-testing.yml`.

Secrets necessários no repositório GitHub:
- `ANDROID_KEYSTORE_BASE64` — keystore em base64: `base64 -w0 ~/.android/easyhealth-release.keystore`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

---

## Depurar login Google

### Checklist OAuth Android

| Item | Valor atual | Onde verificar/configurar |
|---|---|---|
| `applicationId` | `com.EasyHealth.myapp` | `android-config/app-build.gradle` |
| SHA-1 (debug) | obter abaixo | Google Cloud Console → OAuth Credentials |
| SHA-256 (debug) | obter abaixo | Google Cloud Console → OAuth Credentials |
| SHA-1 (release) | da keystore em `~/.android/` | Google Cloud Console → OAuth Credentials |
| Android Client ID | — | Google Cloud Console → APIs & Services |
| Web Client ID | usado no frontend | `.env` do frontend |
| Redirect URI | `com.EasyHealth.myapp:/oauth2redirect` | Google Cloud Console |
| Intent filter | `<intent-filter>` no AndroidManifest | gerado pelo Capacitor / plugin OAuth |

### Obter SHA-1 e SHA-256 da keystore

**Keystore de release:**

```bash
keytool -list -v \
  -keystore ~/.android/easyhealth-release.keystore \
  -alias easyhealth \
  -storepass SUA_SENHA
```

**Keystore de debug** (gerada automaticamente pelo Android Studio):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android
```

Copie os valores `SHA1` e `SHA256` e adicione como impressões digitais no
Google Cloud Console → **APIs & Services → Credentials → seu Android OAuth client**.

### Verificar intent filters

No arquivo gerado `android/app/src/main/AndroidManifest.xml`, verifique se existe:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="com.EasyHealth.myapp" />
</intent-filter>
```

Isso é necessário para o deep link de retorno do OAuth.

---

## Comandos de referência

```bash
npm run android:setup         # setup completo (add + config + sync)
npm run android:sync          # só sync (quando android/ já está pronto)
npm run android:open          # abre Android Studio
npm run android:build:debug   # APK debug (sem assinar com keystore de release)
npm run android:build:aab     # AAB release assinado
npm run android:clean         # limpa outputs do Gradle

# Gradle direto:
cd android
./gradlew projects            # lista módulos (deve mostrar :app)
./gradlew assembleDebug       # APK debug
./gradlew bundleRelease       # AAB release
./gradlew clean               # limpa build

# ADB úteis:
adb devices                   # lista dispositivos/emuladores
adb logcat -s Capacitor       # filtra logs do Capacitor
adb logcat | grep -i google   # filtra logs de autenticação Google
```
