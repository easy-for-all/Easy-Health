"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";
import { AgentOrb } from "@/shared/components/agent-orb";
import { IconWhistle, IconUsers, IconUserPlus } from "@/shared/components/icons";
import Link from "next/link";

const STEPS = [
  { icon: "1", text: "Ative sua conta como Personal Trainer" },
  { icon: "2", text: "Convide alunos pelo código único" },
  { icon: "3", text: "Acompanhe aderência e evolução em tempo real" },
];

type Step = "activate" | "profile";

interface TrainerProfile {
  id?: number;
  display_name?: string;
  bio?: string;
  cref?: string;
}

export default function PersonalOnboardingPage() {
  const router = useRouter();
  const { user, updateUser } = useAuth();
  const [loading, setLoading] = useState(false);
  const [step, setStep] = useState<Step>("activate");
  const [displayName, setDisplayName] = useState(user?.name ?? "");
  const [bio, setBio] = useState("");
  const [cref, setCref] = useState("");
  const [savingProfile, setSavingProfile] = useState(false);

  useEffect(() => {
    if (user?.account_type === "personal_trainer") {
      api.get<TrainerProfile>("/api/v1/trainer/profile").then((data) => {
        if (data?.id) {
          router.replace("/personal/dashboard");
        } else {
          setStep("profile");
        }
      }).catch(() => {
        setStep("profile");
      });
    }
  }, [user?.account_type, router]);

  async function handleActivate() {
    setLoading(true);
    try {
      const data = await api.post<{ account_type: string }>("/api/v1/personal/activate", {});
      updateUser({ account_type: data.account_type as "personal_trainer" });
      setStep("profile");
    } finally {
      setLoading(false);
    }
  }

  async function handleSaveProfile() {
    setSavingProfile(true);
    try {
      await api.post("/api/v1/trainer/profile", {
        display_name: displayName.trim() || user?.name,
        bio: bio.trim(),
        cref: cref.trim(),
      });
      router.push("/personal/dashboard");
    } finally {
      setSavingProfile(false);
    }
  }

  if (step === "profile") {
    return (
      <main
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          minHeight: "100svh",
          padding: "32px 24px",
          background: "var(--bg)",
        }}
      >
        <div style={{ width: "100%", maxWidth: 360, display: "flex", flexDirection: "column", gap: 0 }}>
          <div style={{ textAlign: "center", marginBottom: 28 }}>
            <span style={{ fontSize: 40 }}>🎉</span>
            <h1 className="h-lg" style={{ marginTop: 12, marginBottom: 6 }}>Conta ativada!</h1>
            <p style={{ fontSize: 14, color: "var(--text-muted)", lineHeight: 1.5 }}>
              Complete seu perfil de personal para que os alunos possam te identificar.
            </p>
          </div>

          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--r-lg)",
              padding: "20px 16px",
              marginBottom: 20,
              display: "flex",
              flexDirection: "column",
              gap: 14,
            }}
          >
            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: "var(--text-muted)", display: "block", marginBottom: 6 }}>
                Nome de exibição
              </label>
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Como os alunos vão te ver"
                style={{
                  width: "100%",
                  padding: "10px 12px",
                  borderRadius: "var(--r-md)",
                  border: "1px solid var(--border)",
                  background: "var(--bg)",
                  color: "var(--text)",
                  fontSize: 14,
                  boxSizing: "border-box",
                }}
              />
            </div>

            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: "var(--text-muted)", display: "block", marginBottom: 6 }}>
                Bio curta <span style={{ fontWeight: 400, opacity: 0.7 }}>(opcional)</span>
              </label>
              <textarea
                value={bio}
                onChange={(e) => setBio(e.target.value)}
                placeholder="Ex: Especialista em hipertrofia e emagrecimento"
                rows={3}
                style={{
                  width: "100%",
                  padding: "10px 12px",
                  borderRadius: "var(--r-md)",
                  border: "1px solid var(--border)",
                  background: "var(--bg)",
                  color: "var(--text)",
                  fontSize: 14,
                  resize: "none",
                  boxSizing: "border-box",
                  fontFamily: "inherit",
                }}
              />
            </div>

            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: "var(--text-muted)", display: "block", marginBottom: 6 }}>
                CREF <span style={{ fontWeight: 400, opacity: 0.7 }}>(opcional)</span>
              </label>
              <input
                type="text"
                value={cref}
                onChange={(e) => setCref(e.target.value)}
                placeholder="Ex: 123456-G/SP"
                style={{
                  width: "100%",
                  padding: "10px 12px",
                  borderRadius: "var(--r-md)",
                  border: "1px solid var(--border)",
                  background: "var(--bg)",
                  color: "var(--text)",
                  fontSize: 14,
                  boxSizing: "border-box",
                }}
              />
            </div>
          </div>

          <button
            onClick={handleSaveProfile}
            disabled={savingProfile}
            style={{
              width: "100%",
              padding: "14px",
              borderRadius: "var(--r-lg)",
              background: "var(--primary)",
              color: "var(--on-primary)",
              border: "none",
              fontSize: 15,
              fontWeight: 700,
              cursor: savingProfile ? "not-allowed" : "pointer",
              opacity: savingProfile ? 0.7 : 1,
              marginBottom: 10,
              minHeight: 52,
            }}
          >
            {savingProfile ? "Salvando..." : "Entrar no Painel"}
          </button>

          <button
            onClick={() => router.push("/personal/dashboard")}
            style={{
              width: "100%",
              padding: "12px",
              borderRadius: "var(--r-lg)",
              border: "1.5px solid var(--border)",
              background: "transparent",
              color: "var(--text-muted)",
              fontSize: 14,
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            Pular por agora
          </button>
        </div>
      </main>
    );
  }

  return (
    <main
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        minHeight: "100svh",
        padding: "32px 24px",
        background: "var(--bg)",
        gap: 0,
      }}
    >
      <div style={{ width: "100%", maxWidth: 360, display: "flex", flexDirection: "column", alignItems: "center", gap: 0 }}>

        {/* Orb with whistle */}
        <div style={{ position: "relative", marginBottom: 24 }}>
          <AgentOrb size="card" glyph pulse />
          <span
            style={{
              position: "absolute",
              bottom: -6,
              right: -10,
              background: "var(--primary-soft)",
              borderRadius: "50%",
              width: 28,
              height: 28,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "var(--primary)",
            }}
          >
            <IconWhistle className="w-4 h-4" />
          </span>
        </div>

        <h1 className="h-lg" style={{ textAlign: "center", marginBottom: 8 }}>
          Painel Personal Trainer
        </h1>
        <p style={{ fontSize: 14, color: "var(--text-muted)", textAlign: "center", marginBottom: 28, lineHeight: 1.5 }}>
          Acompanhe seus alunos, prescreva treinos e monitore aderência — tudo em um só lugar.
        </p>

        {/* Steps */}
        <div
          style={{
            width: "100%",
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--r-lg)",
            padding: "16px",
            marginBottom: 24,
          }}
        >
          {STEPS.map((s, i) => (
            <div
              key={s.icon}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                paddingBottom: i < STEPS.length - 1 ? 14 : 0,
                marginBottom: i < STEPS.length - 1 ? 14 : 0,
                borderBottom: i < STEPS.length - 1 ? "1px solid var(--hairline)" : "none",
              }}
            >
              <span
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: "50%",
                  background: "var(--primary-soft)",
                  color: "var(--primary)",
                  fontSize: 12,
                  fontWeight: 700,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexShrink: 0,
                }}
              >
                {s.icon}
              </span>
              <p style={{ margin: 0, fontSize: 14, color: "var(--text-muted)", lineHeight: 1.4 }}>
                {s.text}
              </p>
            </div>
          ))}
        </div>

        <button
          onClick={handleActivate}
          disabled={loading}
          style={{
            width: "100%",
            padding: "14px",
            borderRadius: "var(--r-lg)",
            background: "var(--primary)",
            color: "var(--on-primary)",
            border: "none",
            fontSize: 15,
            fontWeight: 700,
            cursor: loading ? "not-allowed" : "pointer",
            opacity: loading ? 0.7 : 1,
            marginBottom: 10,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            minHeight: 52,
          }}
        >
          <IconUserPlus className="w-5 h-5" />
          {loading ? "Ativando..." : "Ativar conta Personal Trainer"}
        </button>

        <Link
          href="/personal/dashboard"
          style={{
            width: "100%",
            padding: "13px",
            borderRadius: "var(--r-lg)",
            border: "1.5px solid var(--border)",
            background: "transparent",
            color: "var(--text-muted)",
            fontSize: 14,
            fontWeight: 600,
            cursor: "pointer",
            textAlign: "center",
            textDecoration: "none",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            minHeight: 48,
          }}
        >
          <IconUsers className="w-4 h-4" />
          Ver exemplo do painel
        </Link>

        <button
          onClick={() => router.back()}
          style={{
            marginTop: 16,
            background: "none",
            border: "none",
            color: "var(--text-dim)",
            fontSize: 13,
            cursor: "pointer",
          }}
        >
          Agora não
        </button>
      </div>
    </main>
  );
}
