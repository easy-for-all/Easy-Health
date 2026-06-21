"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { AlertCard, type Alert } from "@/shared/components/personal/alert-card";

export default function PersonalAlertsPage() {
  const router = useRouter();
  const [alerts, setAlerts]           = useState<Alert[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading]         = useState(true);

  useEffect(() => {
    api.get<{ alerts: Alert[]; unread_count: number }>("/api/v1/personal/alerts")
      .then((d) => {
        setAlerts(d.alerts);
        setUnreadCount(d.unread_count);
      })
      .finally(() => setLoading(false));
  }, []);

  const handleRead = async (id: number) => {
    try {
      const data = await api.patch<{ alert: Alert; unread_count: number }>(
        `/api/v1/personal/alerts/${id}/mark_read`, {}
      );
      setAlerts((prev) => prev.map((a) => a.id === id ? { ...a, unread: false } : a));
      setUnreadCount(data.unread_count);
    } catch {
      // ignore
    }
  };

  return (
    <main
      style={{
        minHeight: "100svh",
        background: "var(--bg)",
        padding: "20px 16px 32px",
        maxWidth: 480,
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 20 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Alertas</h1>
        {unreadCount > 0 && (
          <span
            style={{
              background: "var(--hot)",
              color: "#fff",
              borderRadius: "var(--r-pill)",
              padding: "2px 8px",
              fontSize: 11,
              fontWeight: 700,
            }}
          >
            {unreadCount} novo{unreadCount > 1 ? "s" : ""}
          </span>
        )}
      </div>

      {loading && (
        <div style={{ textAlign: "center", padding: "48px 0", color: "var(--text-dim)" }}>
          Carregando...
        </div>
      )}

      {!loading && alerts.length === 0 && (
        <div style={{ textAlign: "center", padding: "48px 0" }}>
          <span style={{ fontSize: 40 }}>✅</span>
          <p className="h-sm" style={{ margin: "12px 0 6px" }}>Nenhum alerta</p>
          <p style={{ fontSize: 13, color: "var(--text-muted)" }}>
            Tudo em ordem por aqui. Alertas aparecem quando alunos ficam inativos ou atingem marcos.
          </p>
        </div>
      )}

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {alerts.map((alert) => (
          <AlertCard key={alert.id} alert={alert} onRead={handleRead} />
        ))}
      </div>
    </main>
  );
}
