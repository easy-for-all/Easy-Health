"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useCreateInvitation } from "@/features/personal/use-personal";
import { CodeCard } from "@/shared/components/ui/code-card";
import { IconUserPlus } from "@/shared/components/icons";

const STEPS = [
  "Gere seu código ou link de convite abaixo",
  "Envie para o aluno pelo WhatsApp, e-mail ou qualquer canal",
  "O aluno entra no app, aceita o convite e define as permissões de compartilhamento",
];

export default function PersonalInvitePage() {
  const router = useRouter();
  const { create, loading, result } = useCreateInvitation();

  const handleShare = () => {
    if (result && typeof navigator.share === "function") {
      navigator.share({
        title: "EasyHealth — Convite do seu Personal",
        text: `Seu personal trainer te convidou para o EasyHealth! Clique para aceitar:`,
        url: result.invite_url,
      }).catch(() => {});
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
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 28 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "none", border: "none", color: "var(--text-muted)", cursor: "pointer", fontSize: 22, padding: 0 }}
        >
          ←
        </button>
        <h1 className="h-lg" style={{ margin: 0 }}>Convidar aluno</h1>
      </div>

      {/* Code card or generate button */}
      {result ? (
        <div style={{ marginBottom: 20 }}>
          <CodeCard
            code={result.invitation_code}
            label="Código do convite"
            hint={`Expira em 72h · ${result.invite_url}`}
            onShare={handleShare}
          />
        </div>
      ) : (
        <button
          onClick={create}
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
            marginBottom: 20,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            minHeight: 52,
          }}
        >
          <IconUserPlus className="w-5 h-5" />
          {loading ? "Gerando código..." : "Gerar código de convite"}
        </button>
      )}

      {/* How it works */}
      <div
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--r-lg)",
          padding: "16px",
        }}
      >
        <p className="eyebrow" style={{ marginBottom: 14 }}>Como funciona</p>
        {STEPS.map((step, i) => (
          <div
            key={i}
            style={{
              display: "flex",
              gap: 12,
              paddingBottom: i < STEPS.length - 1 ? 14 : 0,
              marginBottom: i < STEPS.length - 1 ? 14 : 0,
              borderBottom: i < STEPS.length - 1 ? "1px solid var(--hairline)" : "none",
            }}
          >
            <span
              style={{
                width: 26,
                height: 26,
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
              {i + 1}
            </span>
            <p style={{ margin: 0, fontSize: 13, color: "var(--text-muted)", lineHeight: 1.5 }}>{step}</p>
          </div>
        ))}
      </div>
    </main>
  );
}
