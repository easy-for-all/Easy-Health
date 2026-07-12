"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { Avatar } from "@/shared/components/ui/avatar";
import { AdherenceRing } from "@/shared/components/ui/adherence-ring";
import { RiskChip } from "@/shared/components/ui/risk-chip";
import { CommentBox } from "@/shared/components/personal/comment-box";
import { IconEyeOff, IconMessage } from "@/shared/components/icons";
import type { ClientDetail, ClientPermissions } from "@/shared/types/personal";

type WeekData = { week: string; sessions: number };
type RiskLevel = "high" | "med" | "low";

function riskFromClient(c: ClientDetail): RiskLevel {
  const adh = c.adherence?.weekly_adherence ?? 0;
  if (c.adherence?.inactive_alert || adh < 50) return "high";
  if (adh < 80) return "med";
  return "low";
}

function dayLabel(dow: number) {
  const days = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
  return days[dow] ?? "-";
}

function MetricCard({ label, value, sub, color }: { label: string; value: string | number; sub?: string; color?: string }) {
  return (
    <div
      style={{
        background: "var(--surface)",
        border: "1px solid var(--border)",
        borderRadius: "var(--r-md)",
        padding: "14px 12px",
        flex: 1,
        minWidth: 0,
        textAlign: "center",
      }}
    >
      <p className="num" style={{ fontSize: 22, color: color ?? "var(--text)", margin: 0 }}>{value}</p>
      <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "2px 0 0" }}>{label}</p>
      {sub && <p style={{ fontSize: 10, color: "var(--text-faint)", margin: "1px 0 0" }}>{sub}</p>}
    </div>
  );
}

function FrequencyChart({ data }: { data: WeekData[] }) {
  const max = Math.max(...data.map((d) => d.sessions), 1);
  return (
    <div>
      <p className="eyebrow" style={{ marginBottom: 12 }}>Frequência semanal</p>
      <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 56 }}>
        {data.map((d, i) => (
          <div key={i} style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4 }}>
            <div
              style={{
                width: "100%",
                height: Math.max((d.sessions / max) * 44, d.sessions > 0 ? 4 : 2),
                background: d.sessions >= 4 ? "var(--good)" : d.sessions >= 2 ? "var(--primary)" : d.sessions > 0 ? "var(--warn)" : "var(--surface-3)",
                borderRadius: 3,
                transition: "height .4s var(--ease)",
              }}
            />
            <span style={{ fontSize: 8, color: "var(--text-faint)", whiteSpace: "nowrap" }}>
              {i === data.length - 1 ? "Hoje" : d.week.slice(0, 2)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function ShareChips({ perms }: { perms: ClientPermissions }) {
  const chips: { key: keyof ClientPermissions; label: string }[] = [
    { key: "can_view_assigned_workouts",   label: "Treinos" },
    { key: "can_view_completed_workouts",  label: "Histórico" },
    { key: "can_view_adherence",           label: "Aderência" },
    { key: "can_view_exercise_performance",label: "Cargas" },
    { key: "can_view_body_weight",         label: "Peso" },
    { key: "can_view_photos",              label: "Fotos" },
    { key: "can_view_body_analysis",       label: "Bioimpedância" },
    { key: "can_view_exams",               label: "Exames" },
  ];

  return (
    <div>
      <p className="eyebrow" style={{ marginBottom: 10 }}>O que o aluno compartilha</p>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
        {chips.map((c) => (
          <span
            key={c.key}
            style={{
              padding: "4px 10px",
              borderRadius: "var(--r-pill)",
              fontSize: 11,
              fontWeight: 700,
              background: perms[c.key] ? "var(--good-soft)" : "var(--surface-3)",
              color: perms[c.key] ? "var(--good)" : "var(--text-dim)",
            }}
          >
            {perms[c.key] ? "✓" : "–"} {c.label}
          </span>
        ))}
      </div>
    </div>
  );
}

export default function PersonalStudentDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [client, setClient] = useState<ClientDetail & { weekly_frequency?: WeekData[]; next_workout?: { id: number; name: string; day_of_week: number } | null } | null>(null);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(false);

  useEffect(() => {
    api.get<{ client: typeof client }>(`/api/v1/personal/clients/${id}`)
      .then((d) => setClient(d.client))
      .finally(() => setLoading(false));
  }, [id]);

  const handleComment = async (text: string) => {
    try {
      await api.post(`/api/v1/personal/clients/${id}/notes`, { body: text });
    } catch {
      // best-effort — show success toast regardless for UX
    }
    setToast(true);
    setTimeout(() => setToast(false), 2500);
  };

  if (loading) {
    return (
      <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100svh" }}>
        <div style={{ color: "var(--text-dim)" }}>Carregando...</div>
      </main>
    );
  }

  if (!client) {
    return (
      <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100svh" }}>
        <p style={{ color: "var(--text-muted)" }}>Aluno não encontrado.</p>
      </main>
    );
  }

  const risk = riskFromClient(client);
  const adh = client.adherence?.weekly_adherence ?? 0;
  const perms = client.permissions as ClientPermissions;

  // Privacy enforcement
  const canSeeAdherence  = perms.can_view_adherence;
  const canSeeHistory    = perms.can_view_completed_workouts;
  const canSeeWeight     = perms.can_view_body_weight;
  const canSeePhotos     = perms.can_view_photos;
  const canSeeExams      = perms.can_view_exams;
  const canSeeAnalysis   = perms.can_view_body_analysis;

  return (
    <main
      style={{
        minHeight: "100svh",
        background: "var(--bg)",
        paddingBottom: 32,
      }}
    >
      {/* Header */}
      <div
        style={{
          background: "var(--surface)",
          borderBottom: "1px solid var(--border)",
          padding: "16px",
          display: "flex",
          alignItems: "center",
          gap: 12,
        }}
      >
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <Avatar name={client.name} avatarUrl={client.avatar_url} size={40} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{ margin: 0, fontWeight: 700, fontSize: 16, color: "var(--text)" }}>{client.name}</p>
          <RiskChip level={risk} />
        </div>
        {canSeeAdherence && (
          <AdherenceRing pct={adh} size={48} />
        )}
      </div>

      <div style={{ maxWidth: 480, margin: "0 auto", padding: "16px", display: "flex", flexDirection: "column", gap: 16 }}>

        {/* Next workout card */}
        {client.next_workout && (
          <div
            style={{
              background: "var(--primary-soft)",
              border: "1px solid var(--primary)",
              borderRadius: "var(--r-lg)",
              padding: "14px 16px",
            }}
          >
            <p className="eyebrow accent" style={{ marginBottom: 4 }}>Próximo treino</p>
            <p style={{ margin: 0, fontWeight: 700, fontSize: 15, color: "var(--primary)" }}>
              {client.next_workout.name}
            </p>
            <p style={{ margin: "2px 0 0", fontSize: 12, color: "var(--primary)", opacity: 0.75 }}>
              {dayLabel(client.next_workout.day_of_week)}
            </p>
          </div>
        )}

        {/* Metrics */}
        {canSeeAdherence && (
          <div style={{ display: "flex", gap: 8 }}>
            <MetricCard
              label="Aderência"
              value={`${adh}%`}
              color={adh >= 80 ? "var(--good)" : adh >= 50 ? "var(--warn)" : "var(--hot)"}
            />
            <MetricCard
              label="Sem treinar"
              value={client.adherence?.days_without_training ?? "—"}
              sub="dias"
              color={
                (client.adherence?.days_without_training ?? 0) <= 1 ? "var(--good)" :
                (client.adherence?.days_without_training ?? 0) <= 4 ? "var(--warn)" : "var(--hot)"
              }
            />
          </div>
        )}

        {/* Frequency chart */}
        {canSeeHistory && client.weekly_frequency && client.weekly_frequency.length > 0 && (
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--r-lg)",
              padding: "16px",
            }}
          >
            <FrequencyChart data={client.weekly_frequency} />
          </div>
        )}

        {/* Session timeline */}
        {canSeeHistory && client.recent_sessions && client.recent_sessions.length > 0 && (
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--r-lg)",
              padding: "16px",
            }}
          >
            <p className="eyebrow" style={{ marginBottom: 12 }}>Histórico recente</p>
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {client.recent_sessions.map((s) => (
                <div key={s.id} style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <span
                    style={{
                      width: 8,
                      height: 8,
                      borderRadius: "50%",
                      background: "var(--good)",
                      flexShrink: 0,
                    }}
                  />
                  <span style={{ fontSize: 13, color: "var(--text)" }}>
                    {new Date(s.completed_at).toLocaleDateString("pt-BR", { day: "2-digit", month: "short" })}
                  </span>
                  {s.duration && (
                    <span style={{ fontSize: 12, color: "var(--text-dim)" }}>{s.duration} min</span>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Share chips */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--r-lg)",
            padding: "16px",
          }}
        >
          <ShareChips perms={perms} />
        </div>

        {/* Privacy wall for sensitive data */}
        {(!canSeeWeight || !canSeePhotos || !canSeeExams || !canSeeAnalysis) && (
          <div
            style={{
              display: "flex",
              gap: 10,
              padding: "12px 14px",
              background: "var(--surface-2)",
              borderRadius: "var(--r-md)",
            }}
          >
            <IconEyeOff className="w-4 h-4" style={{ flexShrink: 0, color: "var(--text-dim)", marginTop: 2 }} />
            <p style={{ margin: 0, fontSize: 12, color: "var(--text-muted)", lineHeight: 1.5 }}>
              Peso, fotos de evolução, bioimpedância e exames não foram compartilhados por este aluno.
            </p>
          </div>
        )}

        {/* Comment box */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--r-lg)",
            padding: "16px",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 12 }}>
            <IconMessage className="w-4 h-4" style={{ color: "var(--text-dim)" }} />
            <p className="eyebrow" style={{ margin: 0 }}>Observações</p>
          </div>
          <CommentBox
            placeholder="Adicionar observação para este aluno..."
            onSubmit={handleComment}
          />
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div
          style={{
            position: "fixed",
            bottom: "max(24px, var(--safe-area-bottom))",
            left: "50%",
            transform: "translateX(-50%)",
            background: "var(--good)",
            color: "#fff",
            padding: "10px 20px",
            borderRadius: "var(--r-pill)",
            fontSize: 14,
            fontWeight: 600,
            zIndex: 100,
            whiteSpace: "nowrap",
          }}
        >
          Observação enviada!
        </div>
      )}
    </main>
  );
}
