"use client";

// Device-level push diagnostics — ADMIN ONLY (the whole /admin page is gated by
// user.admin). Unlike PushActivationSection (aggregate metrics), this inspects
// and exercises push ON THIS DEVICE. It never shows the raw FCM token, only the
// mask captured during registration.
import { useCallback, useEffect, useState } from "react";
import { useToast } from "@/shared/components/ui/toast-provider";
import {
  collectPushDiagnostics,
  ensurePushTokenRegistered,
  getPushPermissionState,
  openAppNotificationSettings,
  requestApiTestPush,
  requestPushPermissionAndRegister,
  sendLocalTestNotification,
  type PushDiagnosticsSnapshot,
} from "@/shared/lib/pushNotifications";

function Row({ label, value }: { label: string; value: string | number | boolean | null }) {
  const text = value === null || value === undefined ? "—" : String(value);
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-[var(--border)] py-1.5 last:border-0">
      <span className="text-xs text-[var(--text-dim)]">{label}</span>
      <span className="text-right text-xs font-semibold text-[var(--text)] break-all">{text}</span>
    </div>
  );
}

function Btn({ label, onClick, busy }: { label: string; onClick: () => void; busy?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={busy}
      className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-xs font-semibold text-[var(--text)] disabled:opacity-50"
    >
      {label}
    </button>
  );
}

function buildReport(s: PushDiagnosticsSnapshot): string {
  // Deliberately excludes anything token-raw; maskedToken is already masked.
  return [
    "EasyHealth push diagnostics",
    `platform: ${s.platform} (native=${s.isNative})`,
    `permission: ${s.permissionState}`,
    `masked_token: ${s.maskedToken ?? "-"}`,
    `token_synced_to_api: ${s.tokenSyncedToApi ?? "-"} (last_status=${s.lastApiStatus ?? "-"})`,
    `last_registration_at: ${s.lastRegistrationAt ?? "-"}`,
    `channel_id: ${s.channelId}`,
    `app_version: ${s.appVersion ?? "-"} build: ${s.build ?? "-"}`,
    `last_foreground: ${s.lastForeground ? `${s.lastForeground.title ?? ""}@${s.lastForeground.at}` : "-"}`,
    `last_tap: ${s.lastAction ? `${s.lastAction.type ?? ""}→${s.lastAction.path ?? ""}@${s.lastAction.at}` : "-"}`,
    `firebase: ${s.firebaseHint}`,
  ].join("\n");
}

export function PushDiagnosticsSection() {
  const toast = useToast();
  const [snap, setSnap] = useState<PushDiagnosticsSnapshot | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    setSnap(await collectPushDiagnostics());
  }, []);

  useEffect(() => {
    let active = true;
    (async () => {
      const s = await collectPushDiagnostics();
      if (active) setSnap(s);
    })();
    return () => {
      active = false;
    };
  }, []);

  const run = useCallback(
    async (label: string, fn: () => Promise<unknown>) => {
      setBusy(true);
      try {
        const result = await fn();
        await refresh();
        toast.show(`${label}: ${result === false ? "indisponível" : "ok"}`, {
          variant: result === false ? "hot" : "good",
        });
      } catch {
        toast.show(`${label}: erro`, { variant: "hot" });
      } finally {
        setBusy(false);
      }
    },
    [refresh, toast],
  );

  const copyReport = useCallback(async () => {
    if (!snap) return;
    try {
      await navigator.clipboard.writeText(buildReport(snap));
      toast.show("Relatório copiado (sem token completo).", { variant: "good" });
    } catch {
      toast.show("Não foi possível copiar.", { variant: "hot" });
    }
  }, [snap, toast]);

  const remoteTest = useCallback(async () => {
    setBusy(true);
    try {
      const res = await requestApiTestPush();
      await refresh();
      toast.show(
        res.ok ? "Push remoto solicitado (veja o aparelho)." : `Falhou: ${res.errorCode ?? res.status ?? "erro"}`,
        { variant: res.ok ? "good" : "hot" },
      );
    } finally {
      setBusy(false);
    }
  }, [refresh, toast]);

  return (
    <section className="mt-8">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
        Diagnóstico de push (este aparelho)
      </h2>

      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
        {snap ? (
          <>
            <Row label="Plataforma" value={`${snap.platform} (nativo=${snap.isNative})`} />
            <Row label="Permissão" value={snap.permissionState} />
            <Row label="Token (mascarado)" value={snap.maskedToken} />
            <Row label="Token enviado à API" value={snap.tokenSyncedToApi} />
            <Row label="Último status API" value={snap.lastApiStatus} />
            <Row label="Último registro" value={snap.lastRegistrationAt} />
            <Row label="Canal" value={snap.channelId} />
            <Row label="App version / build" value={`${snap.appVersion ?? "—"} / ${snap.build ?? "—"}`} />
            <Row
              label="Última notif. (foreground)"
              value={snap.lastForeground ? `${snap.lastForeground.title ?? ""} @ ${snap.lastForeground.at}` : null}
            />
            <Row
              label="Último clique / deep link"
              value={snap.lastAction ? `${snap.lastAction.type ?? ""} → ${snap.lastAction.path ?? ""}` : null}
            />
            <Row label="Firebase" value={snap.firebaseHint} />
          </>
        ) : (
          <p className="text-xs text-[var(--text-dim)]">Coletando…</p>
        )}
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2 md:grid-cols-4">
        <Btn label="Verificar permissão" busy={busy} onClick={() => run("Permissão", async () => { await getPushPermissionState(); return true; })} />
        <Btn label="Solicitar permissão" busy={busy} onClick={() => run("Solicitar", () => requestPushPermissionAndRegister())} />
        <Btn label="Registrar FCM" busy={busy} onClick={() => run("Registro", () => ensurePushTokenRegistered("permission_granted"))} />
        <Btn label="Reenviar token" busy={busy} onClick={() => run("Reenvio", () => ensurePushTokenRegistered("permission_granted"))} />
        <Btn label="Abrir config Android" busy={busy} onClick={() => run("Config", () => openAppNotificationSettings())} />
        <Btn label="Notificação local" busy={busy} onClick={() => run("Local", () => sendLocalTestNotification())} />
        <Btn label="Push remoto (API)" busy={busy} onClick={remoteTest} />
        <Btn label="Copiar relatório" busy={busy} onClick={copyReport} />
      </div>

      <p className="mt-2 text-[11px] text-[var(--text-dim)]">
        &quot;Push remoto&quot; usa o endpoint admin/self <code>POST /api/v1/admin/push_test</code>. Nunca envia para outro usuário.
      </p>
    </section>
  );
}
