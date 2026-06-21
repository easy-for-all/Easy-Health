"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { CodeCard } from "@/shared/components/ui/code-card";
import { StatusPill } from "@/shared/components/ui/status-pill";
import { Avatar } from "@/shared/components/ui/avatar";

interface InviteEntry {
  id: number;
  name: string;
  status: "ok" | "pend" | "warn";
  label: string;
  joined_at?: string;
}

interface PrivacyData {
  referral_code: string;
}

export default function CommunityInvitePage() {
  const router = useRouter();
  const [code, setCode] = useState<string>("");
  const [invites, setInvites] = useState<InviteEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get<PrivacyData>("/api/v1/privacy_settings").then((d) => {
      setCode(d.referral_code ?? "");
    }).finally(() => setLoading(false));
  }, []);

  const handleShare = () => {
    if (typeof navigator.share === "function") {
      navigator.share({
        title: "EasyHealth",
        text: `Treina comigo no EasyHealth! Use meu código: ${code}`,
        url: `${window.location.origin}/join/${code}`,
      }).catch(() => {});
    }
  };

  return (
    <main
      style={{
        maxWidth: 480,
        margin: "0 auto",
        padding: "20px 16px",
        paddingBottom: "calc(var(--nav-pb) + 16px)",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Convidar amigos</h1>
      </div>

      {!loading && (
        <CodeCard
          code={code}
          label="Seu código de convite"
          hint="Amigos que usam seu código aparecem no seu feed de Amigos."
          onShare={handleShare}
        />
      )}

      {/* Como funciona */}
      <div
        style={{
          marginTop: 20,
          padding: "16px",
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--r-lg)",
        }}
      >
        <p className="eyebrow" style={{ marginBottom: 12 }}>Como funciona</p>
        {[
          { n: "1", text: "Compartilhe seu código com amigos" },
          { n: "2", text: "Eles entram no app e usam o código ao se cadastrar" },
          { n: "3", text: "As conquistas deles aparecem no seu feed de Amigos" },
        ].map((step) => (
          <div key={step.n} style={{ display: "flex", gap: 12, marginBottom: 12 }}>
            <span
              style={{
                width: 24,
                height: 24,
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
              {step.n}
            </span>
            <p style={{ margin: 0, fontSize: 14, color: "var(--text-muted)", lineHeight: 1.4 }}>{step.text}</p>
          </div>
        ))}
      </div>

      {/* Histórico */}
      {invites.length > 0 && (
        <section style={{ marginTop: 24 }}>
          <p className="eyebrow" style={{ marginBottom: 12 }}>Histórico de convites</p>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {invites.map((inv) => (
              <div
                key={inv.id}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 10,
                  padding: "12px 14px",
                  background: "var(--surface)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--r-md)",
                }}
              >
                <Avatar name={inv.name} size={36} />
                <span style={{ flex: 1, fontSize: 14, fontWeight: 600, color: "var(--text)" }}>{inv.name}</span>
                <StatusPill kind={inv.status} label={inv.label} />
              </div>
            ))}
          </div>
        </section>
      )}
    </main>
  );
}
