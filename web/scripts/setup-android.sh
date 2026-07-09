#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/.."
cd "$WEB_DIR"

echo "=== EasyHealth — Setup Android ==="

# ------------------------------------------------------------------
# 1. Regenerate android/ if the Gradle scaffold is missing.
#    This happens after a clean clone or if android/ was partially
#    deleted. The full structure requires `cap add android`, not just
#    `cap sync android`.
# ------------------------------------------------------------------
if [ ! -f "android/gradlew" ]; then
  echo "▶ android/gradlew não encontrado — recriando projeto Android..."
  rm -rf android/
  npx cap add android
  echo "✔ Projeto Android criado"
else
  echo "✔ android/ já está completo"
fi

# ------------------------------------------------------------------
# 2. Overwrite generated files with project-specific config.
#    android-config/ is versioned and takes precedence over what
#    Capacitor generates by default.
# ------------------------------------------------------------------
echo "▶ Aplicando android-config..."
cp android-config/build.gradle android/build.gradle
cp android-config/app-build.gradle android/app/build.gradle
cp android-config/gradle.properties android/gradle.properties
mkdir -p android/gradle/wrapper
cp android-config/gradle/wrapper/gradle-wrapper.properties \
   android/gradle/wrapper/gradle-wrapper.properties
chmod +x android/gradlew

# ------------------------------------------------------------------
# 3. Write local.properties with the best available Android SDK path.
#    Android Studio on Windows generates this file with a Windows path
#    that WSL can't resolve. We overwrite it with a WSL-compatible path.
# ------------------------------------------------------------------
echo "▶ Configurando local.properties..."
SDK_DIR=""

# Prefer the Android Studio SDK installed on Windows (accessible via /mnt/c)
for candidate in /mnt/c/Users/*/AppData/Local/Android/Sdk; do
  if [ -d "$candidate/platform-tools" ]; then
    SDK_DIR="$candidate"
    break
  fi
done

# Fall back to the CLI SDK installed by build-android-local.sh
if [ -z "$SDK_DIR" ] && [ -d "$HOME/android-sdk/platform-tools" ]; then
  SDK_DIR="$HOME/android-sdk"
fi

if [ -n "$SDK_DIR" ]; then
  echo "sdk.dir=$SDK_DIR" > android/local.properties
  echo "✔ SDK: $SDK_DIR"
else
  echo "⚠️  Android SDK não encontrado. local.properties não foi atualizado."
  echo "   Rode npm run android:build:aab para instalar o SDK em ~/android-sdk."
fi

# ------------------------------------------------------------------
# 4. Sync web assets and plugin code into the Android project.
# ------------------------------------------------------------------
echo "▶ Sincronizando Capacitor..."
npx cap sync android

echo ""
echo "✅ Setup Android concluído."
echo "   Para abrir no Android Studio: npm run android:open"
echo "   Para build debug:             npm run android:build:debug"
