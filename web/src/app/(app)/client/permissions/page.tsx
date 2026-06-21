"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { ToggleRow } from "@/shared/components/ui/toggle-row";
import { IconLock, IconUserCheck } from "@/shared/components/icons";
import type { ClientPermissions } from "@/shared/types/personal";

interface TrainerInfo {
  personal_name: string;
  relationship_id: number;
  permissions: ClientPermissions;
}

type PermKey = keyof ClientPermissions;

const PERMISSION_CONFIG: { key: PermKey; label: string; hint: string; sensitive?: boolean }[] = [
  { key: "can_view_assigned_workouts",   label: "Treinos prescritos",    hint: "Seu personal pode ver os treinos que ele criou para você" },
  { key: "can_view_completed_workouts",  label: "Histórico de treinos",  hint: "Sessões concluídas e duração" },
  { key: "can_view_adherence",           label: "Aderência",             hint: "Com que frequência você treina" },
  { key: "can_view_exercise_performance",label: "Desempenho nos exercícios", hint: "Cargas, séries e repetições registradas" },
  { key: "can_view_body_weight",         label: "Peso corporal",         hint: "Histórico de peso registrado no app", sensitive: true },
  { key: "can_view_photos",              label: "Fotos de evolução",     hint: "Exige opt-in explícito — off por padrão", sensitive: true },
  { key: "can_view_body_analysis",       label: "Bioimpedância",         hint: "Dados de composição corporal", sensitive: true },
  { key: "can_view_exams",               label: "Exames médicos",        hint: "Sempre privado — não compartilhável", sensitive: true },
];

export default function ClientPermissionsPage() {
  const router = useRouter();
  const [info, setInfo] = useState<TrainerInfo | null>(null);
  const [perms, setPerms] = useState<ClientPermissions | null>(null);
  const [saving, setSaving] = useState(false);
  const [noTrainer, setNoTrainer] = useState(false);
  const [savedKey, setSavedKey] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get<TrainerInfo>("/api/v1/client_permissions")
      .then((data) => {
        setInfo(data);
        setPerms(data.permissions);
      })
      .catch(() => setNoTrainer(true))
      .finally(() => setLoading(false));
  }, []);

  const handleToggle = async (key: PermKey, value: boolean) => {
    if (!perms) return;
    setPerms((prev) => prev ? { ...prev, [key]: value } : prev);
    setSaving(true);
    try {
      await api.patch("/api/v1/client_permissions", { [key]: value });
      setSavedKey(key);
      setTimeout(() => setSavedKey(null), 1500);
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <main style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "100svh" }}>
        <div style={{ color: "var(--text-dim)" }}>Carregando...</div>
      </main>
    );
  }

  if (noTrainer || !perms || !info) {
    return (
      <main style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", minHeight: "100svh", gap: 12, padding: 24 }}>
        <p style={{ textAlign: "center", color: "var(--text-muted)", fontSize: 14 }}>
          Você não tem nenhum Personal Trainer ativo no momento.
        </p>
        <button onClick={() => router.back()} style={{ color: "var(--primary)", background: "none", border: "none", cursor: "pointer", fontWeight: 600 }}>
          ← Voltar
        </button>
      </main>
    );
  }

  return (
    <main
      style={{
        minHeight: "100svh",
        background: "var(--bg)",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 16px)",
        maxWidth: 480,
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 8 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Permissões</h1>
      </div>

      {/* Trainer badge */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "12px 14px",
          background: "var(--primary-soft)",
          border: "1px solid var(--primary)",
          borderRadius: "var(--r-md)",
          marginBottom: 20,
        }}
      >
        <IconUserCheck className="w-5 h-5" style={{ color: "var(--primary)", flexShrink: 0 }} />
        <div>
          <p style={{ margin: 0, fontWeight: 700, fontSize: 14, color: "var(--primary)" }}>
            {info.personal_name}
          </p>
          <p style={{ margin: 0, fontSize: 12, color: "var(--primary)", opacity: 0.75 }}>
            Acompanha seu progresso
          </p>
        </div>
      </div>

      <p style={{ fontSize: 13, color: "var(--text-muted)", marginBottom: 16, lineHeight: 1.5 }}>
        Controle o que seu Personal Trainer pode ver. Você pode alterar isso a qualquer momento.
      </p>

      {/* Permissions */}
      <div
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--r-lg)",
          padding: "0 16px",
          marginBottom: 16,
        }}
      >
        {PERMISSION_CONFIG.map((cfg, i) => {
          const isExams = cfg.key === "can_view_exams";
          const locked  = isExams;
          const value   = locked ? false : (perms[cfg.key] ?? false);

          return (
            <div
              key={cfg.key}
              style={{
                borderBottom: i < PERMISSION_CONFIG.length - 1 ? "1px solid var(--hairline)" : "none",
              }}
            >
              <ToggleRow
                label={
                  cfg.sensitive
                    ? `${cfg.label} ${savedKey === cfg.key ? "✓" : ""}`
                    : cfg.label
                }
                hint={cfg.hint}
                checked={value}
                onChange={(v) => handleToggle(cfg.key, v)}
                locked={locked || saving}
                aria-label={cfg.label}
              />
              {cfg.sensitive && !isExams && (
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 4,
                    paddingBottom: 10,
                    marginTop: -4,
                  }}
                >
                  <IconLock className="w-3 h-3" style={{ color: "var(--text-faint)" }} />
                  <span style={{ fontSize: 10, color: "var(--text-faint)" }}>Sensível — desligado por padrão</span>
                </div>
              )}
              {isExams && (
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 4,
                    paddingBottom: 10,
                    marginTop: -4,
                  }}
                >
                  <IconLock className="w-3 h-3" style={{ color: "var(--hot)" }} />
                  <span style={{ fontSize: 10, color: "var(--hot)", fontWeight: 700 }}>Sempre privado — nunca compartilhado</span>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Privacy note */}
      <div
        style={{
          padding: "12px 14px",
          background: "var(--surface-2)",
          borderRadius: "var(--r-md)",
          fontSize: 12,
          color: "var(--text-muted)",
          lineHeight: 1.5,
        }}
      >
        🔒 Peso, fotos, bioimpedância e exames são sempre opcionais. Nenhum dado é compartilhado sem sua autorização.
      </div>
    </main>
  );
}
