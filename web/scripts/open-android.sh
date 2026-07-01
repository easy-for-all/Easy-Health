#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$SCRIPT_DIR/../android"

STUDIO_WIN="/mnt/c/Program Files/Android/Android Studio/bin/studio64.exe"
STUDIO_LINUX="/usr/local/android-studio/bin/studio.sh"

if [ -f "$STUDIO_WIN" ]; then
  WIN_PATH="$(wslpath -w "$ANDROID_DIR")"
  echo "▶ Abrindo Android Studio (Windows) com projeto: $WIN_PATH"
  "$STUDIO_WIN" "$WIN_PATH" &
elif [ -f "$STUDIO_LINUX" ]; then
  echo "▶ Abrindo Android Studio (Linux)..."
  CAPACITOR_ANDROID_STUDIO_PATH="$STUDIO_LINUX" npx cap open android
else
  echo "❌ Android Studio não encontrado."
  echo "   Windows: $STUDIO_WIN"
  echo "   Linux:   $STUDIO_LINUX"
  echo ""
  echo "   Configure CAPACITOR_ANDROID_STUDIO_PATH ou abra manualmente:"
  echo "   File → Open → $(wslpath -w "$ANDROID_DIR" 2>/dev/null || echo "$ANDROID_DIR")"
  exit 1
fi
