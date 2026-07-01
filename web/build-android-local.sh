#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_SDK_DIR="$HOME/android-sdk"
CMDTOOLS_VERSION="11076708"

echo "=== EasyHealth — Build Android AAB Local ==="

# ──────────────────────────────────────────────
# 1. Android SDK command-line tools
# ──────────────────────────────────────────────
if [ ! -f "$ANDROID_SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "▶ Instalando Android SDK command-line tools..."
  mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
  wget -q --show-progress \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDTOOLS_VERSION}_latest.zip" \
    -O /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdtools-extract
  mv /tmp/cmdtools-extract/cmdline-tools "$ANDROID_SDK_DIR/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/cmdtools-extract
  echo "✔ SDK tools instalados"
fi

export ANDROID_HOME="$ANDROID_SDK_DIR"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

# ──────────────────────────────────────────────
# 2. Plataforma e build-tools
# ──────────────────────────────────────────────
if [ ! -d "$ANDROID_HOME/platforms/android-36" ] || [ ! -d "$ANDROID_HOME/build-tools/36.0.0" ]; then
  echo "▶ Instalando plataforma Android 36 e build-tools..."
  yes | sdkmanager --licenses > /dev/null 2>&1 || true
  sdkmanager "platforms;android-36" "build-tools;36.0.0" "platform-tools"
  echo "✔ Componentes instalados"
fi

# ──────────────────────────────────────────────
# 3. Credenciais de assinatura (keystore local)
#
# Prefira exportar as variáveis abaixo no seu shell ou em um arquivo
# .env.android.local (não commitado) antes de rodar este script:
#   export ANDROID_KEYSTORE_PASSWORD="..."
#   export ANDROID_KEY_PASSWORD="..."
# As senhas hardcoded abaixo são fallback para conveniência local.
# ──────────────────────────────────────────────
export ANDROID_KEYSTORE_PATH="${ANDROID_KEYSTORE_PATH:-$HOME/.android/easyhealth-release.keystore}"
export ANDROID_KEYSTORE_PASSWORD="${ANDROID_KEYSTORE_PASSWORD:-cmOCI0aV3TLPZcjHKIALy1jjbk}"
export ANDROID_KEY_ALIAS="${ANDROID_KEY_ALIAS:-easyhealth}"
export ANDROID_KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-cmOCI0aV3TLPZcjHKIALy1jjbk}"
export ANDROID_VERSION_CODE="${ANDROID_VERSION_CODE:-1}"
export ANDROID_VERSION_NAME="${ANDROID_VERSION_NAME:-1.0.0-local}"

if [ ! -f "$ANDROID_KEYSTORE_PATH" ]; then
  echo "❌ Keystore não encontrado em $ANDROID_KEYSTORE_PATH"
  exit 1
fi

# ──────────────────────────────────────────────
# 4. Setup Android (garante que android/ está completo,
#    aplica android-config e sincroniza Capacitor)
# ──────────────────────────────────────────────
cd "$SCRIPT_DIR"
bash scripts/setup-android.sh

# ──────────────────────────────────────────────
# 5. Verificar google-services.json (Firebase FCM)
# ──────────────────────────────────────────────
GOOGLE_SERVICES="$SCRIPT_DIR/android/app/google-services.json"
if [ ! -f "$GOOGLE_SERVICES" ]; then
  echo ""
  echo "❌ google-services.json não encontrado em android/app/"
  echo ""
  echo "   Para obter este arquivo:"
  echo "   1. Acesse https://console.firebase.google.com"
  echo "   2. Selecione o projeto EasyHealth"
  echo "   3. Configurações do projeto → Seus apps → Android (com.EasyHealth.myapp)"
  echo "   4. Baixe google-services.json e coloque em:"
  echo "      $GOOGLE_SERVICES"
  echo ""
  echo "   Veja web/docs/firebase-push-android.md para instruções completas."
  echo ""
  exit 1
fi
echo "✔ google-services.json encontrado"

# ──────────────────────────────────────────────
# 6. Build
# ──────────────────────────────────────────────
echo "▶ Gerando AAB Release..."
cd "$SCRIPT_DIR/android"
chmod +x gradlew
./gradlew bundleRelease --no-daemon

# ──────────────────────────────────────────────
# 7. Copiar para releases/
# ──────────────────────────────────────────────
RELEASES_DIR="$SCRIPT_DIR/../releases"
mkdir -p "$RELEASES_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="$RELEASES_DIR/app-release-${TIMESTAMP}.aab"
cp "$SCRIPT_DIR/android/app/build/outputs/bundle/release/app-release.aab" "$OUTPUT_FILE"

echo ""
echo "✅ AAB gerado com sucesso!"
echo "   $OUTPUT_FILE"
