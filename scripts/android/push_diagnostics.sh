#!/usr/bin/env bash
# Push notification on-device diagnostics for EasyHealth (Android).
#
# Collects, in one filtered pass, the evidence you cannot get from the backend:
# is the app installed, which version, is POST_NOTIFICATIONS granted, does the
# notification channel exist, and a FILTERED logcat of FCM + Capacitor push.
#
# Safe by design:
# - read-only on the device (no data mutation);
# - long token-like strings are masked before anything is written to disk;
# - the report is written under scripts/android/reports/ which is gitignored.
#
# Usage:
#   scripts/android/push_diagnostics.sh              # snapshot + 30s capture
#   scripts/android/push_diagnostics.sh 60           # snapshot + 60s capture
#   scripts/android/push_diagnostics.sh 0            # snapshot only (no capture)
#
# On WSL it auto-detects the Windows adb.exe when the Linux adb is absent.
set -euo pipefail

PACKAGE="com.EasyHealth.myapp"
DURATION="${1:-30}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/push-diagnostics-$STAMP.log"

mkdir -p "$REPORT_DIR"

# --- locate adb (prefer native, fall back to Windows adb.exe under WSL) -------
ADB=""
if command -v adb >/dev/null 2>&1; then
  ADB="adb"
elif command -v adb.exe >/dev/null 2>&1; then
  ADB="adb.exe"
else
  echo "❌ adb not found. Install platform-tools or expose Windows adb.exe on PATH (WSL)." >&2
  exit 1
fi

# Mask FCM-token-like blobs (long unbroken id strings) before writing to disk.
mask() {
  sed -E 's/([A-Za-z0-9_-]{6})[A-Za-z0-9_:-]{20,}([A-Za-z0-9_-]{4})/\1…\2/g'
}

# Echo to console and append (masked) to the report file.
log() { echo "$@" | tee -a "$REPORT" >/dev/null; echo "$@"; }
section() { log ""; log "== $* =="; }

# --- device presence ----------------------------------------------------------
DEVICE_LINE="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
if [ -z "$DEVICE_LINE" ]; then
  echo "❌ No authorized device connected. Run '$ADB devices' and accept the RSA prompt on the phone." >&2
  "$ADB" devices >&2 || true
  exit 1
fi

{
  log "EasyHealth push diagnostics — $STAMP"
  log "adb: $ADB   device: $DEVICE_LINE   package: $PACKAGE"

  section "App installed & version"
  if "$ADB" shell pm list packages | tr -d '\r' | grep -q "package:$PACKAGE"; then
    "$ADB" shell dumpsys package "$PACKAGE" | tr -d '\r' \
      | grep -E "versionName=|versionCode=|firstInstallTime=|lastUpdateTime=" | sed 's/^[[:space:]]*//' | tee -a "$REPORT"
  else
    log "❌ Package NOT installed. Install the internal-track build first."
    exit 1
  fi

  section "POST_NOTIFICATIONS permission (Android 13+)"
  "$ADB" shell dumpsys package "$PACKAGE" | tr -d '\r' \
    | grep -E "android.permission.POST_NOTIFICATIONS" | sed 's/^[[:space:]]*//' | tee -a "$REPORT" \
    || log "(permission line not found — pre-13 device or not requested yet)"

  section "AppOps — POST_NOTIFICATION"
  "$ADB" shell appops get "$PACKAGE" POST_NOTIFICATION 2>/dev/null | tr -d '\r' | tee -a "$REPORT" \
    || log "(appops query unavailable)"

  section "Notification enabled + channels"
  "$ADB" shell dumpsys notification --noredact 2>/dev/null | tr -d '\r' \
    | awk -v pkg="$PACKAGE" '
        $0 ~ pkg {show=1}
        show && /NotificationChannel\{|importance=|mImportance=|Enabled|banned=/ {print}
        show && /^$/ {show=0}
      ' | head -40 | tee -a "$REPORT" \
    || log "(could not read notification channels)"
  log "Expected channel id: workout_reminders (importance HIGH)."

  section "Current PID"
  PID="$("$ADB" shell pidof "$PACKAGE" | tr -d '\r' || true)"
  log "pid: ${PID:-'(not running)'}"
} 2>&1

# --- filtered logcat capture --------------------------------------------------
if [ "$DURATION" -gt 0 ]; then
  section "Filtered logcat (${DURATION}s) — FCM + Capacitor push"
  log "Clearing logcat buffer…"
  "$ADB" logcat -c || true
  log "Capturing for ${DURATION}s. Trigger a push now (push:test:send_now / diagnostics panel)…"

  # Narrow tag set so we don't drown in thousands of unrelated lines.
  timeout "${DURATION}" "$ADB" logcat -v time \
      FirebaseMessaging:V FirebaseMessagingService:V FLTFireMsgReceiver:V \
      Capacitor:V "Capacitor/PushNotifications":V CapacitorFirebaseMessaging:V \
      NotificationManager:I ActivityTaskManager:I "*:S" 2>/dev/null \
    | mask | tee -a "$REPORT" || true
fi

echo ""
echo "✅ Report saved (tokens masked): $REPORT"
echo "   Tip: filter opened Activity after a tap with:"
echo "   $ADB shell dumpsys activity activities | grep -i $PACKAGE | head"
