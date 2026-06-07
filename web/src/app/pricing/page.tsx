"use client";

import { useState, useCallback } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { PublicLayout } from "@/shared/components/public-layout";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { setPendingPlan, type PendingPlan } from "@/features/billing/checkout-intent";
import { trackCheckoutStarted } from "@/shared/lib/analytics";

const FEATURES = [
  "Treinos personalizados por IA",
  "Plano semanal adaptável",
  "Histórico ilimitado de treinos",
  "Coach EasyHealth (IA conversacional)",
  "Troca de exercícios inteligente",
  "Evolução de carga e gráficos",
  "Suporte academia e treino em casa",
];

export default function PricingPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [loadingPlan, setLoadingPlan] = useState<PendingPlan | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSelectPlan = useCallback(async (plan: PendingPlan) => {
    setError(null);
    setLoadingPlan(plan);
    trackCheckoutStarted(plan, "pricing");

    if (!user) {
      setPendingPlan(plan);
      router.push("/sign-up");
      return;
    }

    try {
      const { checkout_url } = await api.post<{ checkout_url: string }>(
        "/api/v1/billing/checkout",
        { plan }
      );
      window.location.href = checkout_url;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Erro ao iniciar checkout. Tente novamente.");
      setLoadingPlan(null);
    }
  }, [user, router]);

  const isLoading = loadingPlan !== null;

  return (
    <PublicLayout>
      {/* Hero */}
      <section style={{ background: "var(--bg)", padding: "64px 20px 48px", textAlign: "center", borderBottom: "1px solid var(--border)" }}>
        <div style={{ maxWidth: 600, margin: "0 auto" }}>
          <span style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            background: "var(--primary-soft)", color: "var(--primary)",
            border: "1px solid oklch(0.685 0.17 258 / .3)",
            padding: "6px 14px", borderRadius: "var(--r-pill)",
            fontSize: 13, fontWeight: 700, marginBottom: 20,
          }}>
            ✨ 7 dias grátis — sem cartão necessário
          </span>

          <h1 style={{ fontFamily: "var(--font-display)", fontSize: 36, fontWeight: 700, letterSpacing: "-0.025em", margin: "0 0 16px", lineHeight: 1.06, color: "var(--text)" }}>
            Treine melhor com a<br />EasyHealth Pro
          </h1>
          <p style={{ fontSize: 17, color: "var(--text-muted)", margin: "0 0 32px", lineHeight: 1.55 }}>
            Plano de treino personalizado por IA, Coach de bolso e evolução completa em um lugar só.
          </p>

          <a
            href="#planos"
            style={{
              display: "inline-block",
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)", fontWeight: 700, fontSize: 16,
              padding: "16px 32px", borderRadius: "var(--r-pill)",
              boxShadow: "var(--glow)", textDecoration: "none",
            }}
          >
            Começar 7 dias grátis
          </a>
          <p style={{ fontSize: 12, color: "var(--text-dim)", marginTop: 10 }}>
            Cancele quando quiser. Sem compromisso.
          </p>
        </div>
      </section>

      {/* Plan cards */}
      <section id="planos" style={{ maxWidth: 720, margin: "0 auto", padding: "48px 20px 64px" }}>
        {error && (
          <div style={{ background: "var(--hot-soft)", color: "var(--hot)", border: "1px solid oklch(0.70 0.19 28 / .35)", borderRadius: "var(--r-md)", padding: "12px 16px", fontSize: 14, marginBottom: 24, textAlign: "center" }}>
            {error}
          </div>
        )}

        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          {/* Pro Mensal */}
          <PlanCard
            title="Pro Mensal"
            price="R$ 19,90"
            period="/mês"
            sub="Depois de 7 dias grátis"
            features={FEATURES}
            onSelect={() => handleSelectPlan("pro_monthly")}
            loading={loadingPlan === "pro_monthly"}
            disabled={isLoading}
            highlight={false}
          />

          {/* Pro Anual */}
          <PlanCard
            title="Pro Anual"
            price="R$ 118,80"
            period="/ano"
            sub="≈ R$ 9,90/mês"
            savings="Economize ~50%"
            badge="Melhor valor"
            features={["Tudo do Pro Mensal", ...FEATURES.slice(0, 4)]}
            onSelect={() => handleSelectPlan("pro_yearly")}
            loading={loadingPlan === "pro_yearly"}
            disabled={isLoading}
            highlight
          />
        </div>

        <p style={{ textAlign: "center", fontSize: 13, color: "var(--text-dim)", marginTop: 28 }}>
          Já tem conta?{" "}
          <Link href="/login" style={{ color: "var(--primary)", fontWeight: 700, textDecoration: "none" }}>
            Entrar
          </Link>{" "}
          para gerenciar sua assinatura.
        </p>
      </section>
    </PublicLayout>
  );
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

type PlanCardProps = {
  title: string;
  price: string;
  period: string;
  sub?: string;
  savings?: string;
  badge?: string;
  features: string[];
  onSelect: () => void;
  loading: boolean;
  disabled: boolean;
  highlight: boolean;
};

function PlanCard({ title, price, period, sub, savings, badge, features, onSelect, loading, disabled, highlight }: PlanCardProps) {
  return (
    <div
      style={{
        position: "relative",
        background: highlight
          ? "linear-gradient(140deg, var(--primary-soft), var(--surface))"
          : "var(--surface)",
        border: `1.5px solid ${highlight ? "oklch(0.685 0.17 258 / .45)" : "var(--border)"}`,
        borderRadius: "var(--r-xl)",
        padding: "28px 24px 24px",
        boxShadow: highlight ? "var(--glow)" : "none",
      }}
    >
      {/* Badge */}
      {badge && (
        <span style={{
          position: "absolute", top: -14, left: "50%", transform: "translateX(-50%)",
          background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
          color: "var(--on-primary)", fontSize: 12, fontWeight: 700,
          padding: "5px 16px", borderRadius: "var(--r-pill)",
          boxShadow: "var(--glow)", whiteSpace: "nowrap",
        }}>
          ✦ {badge}
        </span>
      )}

      {/* Header */}
      <p style={{ fontFamily: "var(--font-display)", fontSize: 18, fontWeight: 700, margin: "0 0 4px" }}>{title}</p>
      <div style={{ display: "flex", alignItems: "baseline", gap: 4, marginBottom: 4 }}>
        <span style={{ fontFamily: "var(--font-display)", fontSize: 36, fontWeight: 700, color: highlight ? "var(--primary)" : "var(--text)", letterSpacing: "-0.025em" }}>
          {price}
        </span>
        <span style={{ fontSize: 14, color: "var(--text-muted)" }}>{period}</span>
      </div>
      {sub && <p style={{ fontSize: 14, color: highlight ? "var(--primary)" : "var(--text-muted)", margin: "0 0 2px", fontWeight: highlight ? 700 : 400 }}>{sub}</p>}
      {savings && <p style={{ fontSize: 13, color: "var(--good)", fontWeight: 700, margin: "0 0 20px" }}>✓ {savings}</p>}
      {!savings && <div style={{ marginBottom: 20 }} />}

      {/* Features */}
      <ul style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: 24, padding: 0, listStyle: "none" }}>
        {features.map((f) => (
          <li key={f} style={{ display: "flex", alignItems: "flex-start", gap: 10, fontSize: 14, color: "var(--text-muted)" }}>
            <svg viewBox="0 0 24 24" fill="none" stroke="var(--good)" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" style={{ width: 16, height: 16, flexShrink: 0, marginTop: 2 }}>
              <path d="M20 6L9 17l-5-5" />
            </svg>
            {f}
          </li>
        ))}
      </ul>

      {/* CTA */}
      <button
        onClick={onSelect}
        disabled={disabled}
        style={{
          width: "100%", borderRadius: "var(--r-pill)", padding: "16px",
          fontWeight: 700, fontSize: 16, border: 0, cursor: disabled ? "not-allowed" : "pointer",
          background: highlight
            ? "linear-gradient(180deg, var(--primary), var(--primary-2))"
            : "var(--bg-2)",
          color: highlight ? "var(--on-primary)" : "var(--text)",
          boxShadow: highlight ? "var(--glow)" : "none",
          opacity: disabled ? 0.65 : 1,
          transition: "opacity .15s",
        }}
      >
        {loading ? "Aguarde..." : "Começar 7 dias grátis"}
      </button>
      <p style={{ textAlign: "center", fontSize: 12, color: "var(--text-dim)", marginTop: 10 }}>Cancele quando quiser</p>
    </div>
  );
}
