#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/.."
APP_ID="com.EasyHealth.myapp"

echo "=== EasyHealth — Build + Run no emulador Android ==="

# ------------------------------------------------------------------
# 1. Build debug no WSL.
# ------------------------------------------------------------------
echo "▶ Buildando APK debug..."
(cd "$WEB_DIR/android" && ./gradlew assembleDebug --no-daemon)

APK_PATH="$WEB_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
  echo "✖ APK não encontrado em $APK_PATH"
  exit 1
fi

# ------------------------------------------------------------------
# 2. Instalar e abrir no emulador via adb.exe do Windows.
#    O emulador roda no Android Studio do Windows — precisa estar
#    aberto antes de rodar este script.
# ------------------------------------------------------------------
APK_WIN_PATH="$(wslpath -w "$APK_PATH")"

echo "▶ Instalando no emulador (Windows adb.exe)..."
powershell.exe -NoProfile -Command "
  \$adb = \"\$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe\"
  \$devices = & \$adb devices | Select-String 'device$'
  if (-not \$devices) {
    Write-Error 'Nenhum emulador/device autorizado encontrado. Abra o AVD no Android Studio do Windows primeiro.'
    exit 1
  }
  Copy-Item '$APK_WIN_PATH' -Destination \"\$env:TEMP\app-debug.apk\" -Force
  & \$adb install -r \"\$env:TEMP\app-debug.apk\"
  & \$adb shell monkey -p $APP_ID -c android.intent.category.LAUNCHER 1
"

echo "✅ App instalado e aberto no emulador."
