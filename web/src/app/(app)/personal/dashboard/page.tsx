"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { usePersonalDashboard } from "@/features/personal/use-personal";
import { FilterChips } from "@/shared/components/ui/filter-chips";
import { StudentCard, type Student } from "@/shared/components/personal/student-card";
import { IconBell, IconUserPlus } from "@/shared/components/icons";
import type { ClientSummary } from "@/shared/types/personal";

const FILTERS = [
  { id: "all",    label: "Todos"       },
  { id: "alert",  label: "Com alerta"  },
  { id: "active", label: "Em dia"      },
];

function clientToStudent(c: ClientSummary): Student {
  const adherencePct = c.weekly_adherence ?? 0;
  const riskLevel =
    c.inactive_alert || adherencePct < 50 ? "high" :
    adherencePct < 80 ? "med" :
    "low";

  return {
    id:            c.client_id,
    name:          c.name,
    avatarUrl:     c.avatar_url,
    adherencePct,
    riskLevel,
    daysInactive:  c.days_without_training ?? undefined,
  };
}

export default function PersonalDashboardPage() {
  const router = useRouter();
  const { user } = useAuth();
  const { dashboard, clients, loading } = usePersonalDashboard();
  const [filter, setFilter] = useState("all");

  if (!user || user.account_type !== "personal_trainer") {
    return (
      <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100svh" }}>
        <Link
          href="/personal"
          style={{
            padding: "13px 24px",
            borderRadius: "var(--r-lg)",
            background: "var(--primary)",
            color: "var(--on-primary)",
            fontWeight: 700,
            textDecoration: "none",
          }}
        >
          Ativar conta Personal Trainer
        </Link>
      </main>
    );
  }

  const filteredClients = clients.filter((c) => {
    if (filter === "alert") return c.inactive_alert || (c.weekly_adherence ?? 0) < 50;
    if (filter === "active") return !c.inactive_alert && (c.weekly_adherence ?? 0) >= 80;
    return true;
  });

  const alertCount = clients.filter((c) => c.inactive_alert || (c.weekly_adherence ?? 0) < 50).length;

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
          padding: "20px 16px 16px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <button
            onClick={() => router.back()}
            aria-label="Voltar"
            style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
          >
            ←
          </button>
          <h1 className="h-md" style={{ margin: 0 }}>Painel Personal</h1>
        </div>

        <div style={{ display: "flex", gap: 8 }}>
          <Link
            href="/personal/alerts"
            aria-label="Alertas"
            style={{
              position: "relative",
              width: 40,
              height: 40,
              borderRadius: "var(--r-sm)",
              background: alertCount > 0 ? "var(--hot-soft)" : "var(--surface-2)",
              color: alertCount > 0 ? "var(--hot)" : "var(--text-muted)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              textDecoration: "none",
            }}
          >
            <IconBell className="w-5 h-5" />
            {alertCount > 0 && (
              <span
                style={{
                  position: "absolute",
                  top: -4,
                  right: -4,
                  background: "var(--hot)",
                  color: "#fff",
                  borderRadius: "50%",
                  width: 18,
                  height: 18,
                  fontSize: 10,
                  fontWeight: 700,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                {alertCount}
              </span>
            )}
          </Link>
        </div>
      </div>

      <div style={{ maxWidth: 480, margin: "0 auto", padding: "20px 16px", display: "flex", flexDirection: "column", gap: 16 }}>

        {/* Stats strip */}
        {!loading && dashboard && (
          <div style={{ display: "flex", gap: 8 }}>
            {[
              { label: "Ativos", value: dashboard.active_clients, color: "var(--text)" },
              { label: "Em risco", value: dashboard.inactive_7_days, color: "var(--hot)" },
              { label: "Aderência alta", value: dashboard.high_adherence, color: "var(--good)" },
            ].map((stat) => (
              <div
                key={stat.label}
                style={{
                  flex: 1,
                  background: "var(--surface)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--r-md)",
                  padding: "12px 8px",
                  textAlign: "center",
                }}
              >
                <p className="num" style={{ fontSize: 24, color: stat.color, margin: 0 }}>{stat.value}</p>
                <p style={{ fontSize: 11, color: "var(--text-dim)", margin: "2px 0 0" }}>{stat.label}</p>
              </div>
            ))}
          </div>
        )}

        {/* Action */}
        <Link
          href="/personal/invite"
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            padding: "13px",
            borderRadius: "var(--r-lg)",
            background: "var(--primary)",
            color: "var(--on-primary)",
            fontWeight: 700,
            fontSize: 14,
            textDecoration: "none",
          }}
        >
          <IconUserPlus className="w-5 h-5" />
          Convidar aluno
        </Link>

        {/* Filter */}
        <FilterChips chips={FILTERS} active={filter} onChange={setFilter} />

        {/* Client list */}
        {loading && (
          <div style={{ textAlign: "center", padding: "32px 0", color: "var(--text-dim)" }}>
            Carregando...
          </div>
        )}

        {!loading && filteredClients.length === 0 && (
          <div style={{ textAlign: "center", padding: "48px 0" }}>
            <span style={{ fontSize: 36 }}>🎯</span>
            <p className="h-sm" style={{ margin: "12px 0 6px" }}>
              {filter === "all" ? "Nenhum aluno ainda" : "Nenhum aluno neste filtro"}
            </p>
            {filter === "all" && (
              <p style={{ fontSize: 13, color: "var(--text-muted)" }}>
                Convide alunos e eles aparecerão aqui.
              </p>
            )}
          </div>
        )}

        {!loading && filteredClients.map((c) => (
          <StudentCard key={c.client_id} student={clientToStudent(c)} />
        ))}
      </div>
    </main>
  );
}
