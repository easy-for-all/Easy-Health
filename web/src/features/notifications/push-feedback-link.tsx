"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BottomSheet } from "@/shared/components/ui/bottom-sheet";
import { api } from "@/shared/lib/api";
import { trackEvent } from "@/shared/lib/analytics";
import { useToast } from "@/shared/components/ui/toast-provider";

// Discreet "não gostei deste lembrete" action, shown only when the screen was
// opened from a push (?from_push=<delivery_id>). Never a primary button.
const REASONS: { value: string; label: string }[] = [
  { value: "bad_time", label: "Horário ruim" },
  { value: "too_many", label: "Recebi notificações demais" },
  { value: "trained_elsewhere", label: "Já treinei por outro meio" },
  { value: "not_this_type", label: "Não quero esse tipo de lembrete" },
];

export function PushFeedbackLink() {
  const router = useRouter();
  const toast = useToast();
  const [deliveryId, setDeliveryId] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    try {
      const id = new URLSearchParams(window.location.search).get("from_push");
      if (id) setDeliveryId(id);
    } catch {
      /* ignore */
    }
  }, []);

  if (!deliveryId) return null;

  async function submit(reason: string) {
    setOpen(false);
    try {
      await api.post(`/api/v1/notification_deliveries/${deliveryId}/dislike`, { reason });
      trackEvent("notification_disliked", { platform: "android", reason, delivery_id: deliveryId ?? undefined });
    } catch {
      /* best-effort */
    }
    if (reason === "bad_time") {
      router.push("/settings");
    } else {
      toast.show("Obrigado pelo retorno. Ajustamos seus lembretes.", { variant: "default" });
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        style={{
          display: "block", width: "100%", textAlign: "center", marginTop: 12,
          background: "transparent", border: 0, cursor: "pointer",
          color: "var(--text-muted)", fontSize: 12,
        }}
      >
        Não gostei deste lembrete
      </button>

      <BottomSheet open={open} onClose={() => setOpen(false)} ariaLabel="Feedback do lembrete">
        <div style={{ padding: "8px 4px 16px" }}>
          <p style={{ fontWeight: 700, fontSize: 15, margin: "0 0 12px" }}>O que não funcionou?</p>
          <div style={{ display: "grid", gap: 8 }}>
            {REASONS.map((r) => (
              <button
                key={r.value}
                onClick={() => submit(r.value)}
                style={{
                  width: "100%", textAlign: "left", padding: "14px 16px",
                  borderRadius: "var(--r-md)", border: "1px solid var(--border)",
                  background: "var(--surface)", color: "var(--text)", fontSize: 14, cursor: "pointer",
                }}
              >
                {r.label}
              </button>
            ))}
          </div>
        </div>
      </BottomSheet>
    </>
  );
}
