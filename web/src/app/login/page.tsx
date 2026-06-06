"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { getPendingPlan, clearPendingPlan } from "@/features/billing/checkout-intent";

export default function LoginPage() {
  const { signIn } = useAuth();
  const router = useRouter();
  const t = useTranslations("auth");
  const [email, setEmail]       = useState("");
  const [password, setPassword] = useState("");
  const [error, setError]       = useState("");
  const [loading, setLoading]   = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await signIn(email, password);
      const pending = getPendingPlan();
      if (pending) {
        clearPendingPlan();
        const { checkout_url } = await api.post<{ checkout_url: string }>(
          "/api/v1/billing/checkout",
          { plan: pending }
        );
        window.location.href = checkout_url;
      } else {
        router.push("/dashboard");
      }
    } catch (err) {
      if (err instanceof ApiError)       setError(err.message);
      else if (err instanceof TypeError) setError("Não foi possível conectar ao servidor. Tente novamente.");
      else                               setError(t("loginError"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div
      style={{
        display: "flex", minHeight: "100svh", alignItems: "center",
        justifyContent: "center", padding: "24px 20px",
        background: "var(--bg)",
        backgroundImage: "radial-gradient(130% 90% at 50% -20%, oklch(0.30 0.06 258 / .35), transparent 60%)",
      }}
    >
      <div style={{ width: "100%", maxWidth: 360 }}>
        {/* Brand glyph */}
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: 40, gap: 12 }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="EasyHealth" style={{ width: 64, height: 64, borderRadius: 20 }} />
          <div style={{ textAlign: "center" }}>
            <p style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 22, letterSpacing: "-0.02em", margin: 0 }}>
              EasyHealth
            </p>
            <p style={{ fontSize: 14, color: "var(--text-muted)", margin: "4px 0 0" }}>
              Seu personal trainer de IA
            </p>
          </div>
        </div>

        {/* Error */}
        {error && (
          <div style={{ background: "var(--hot-soft)", border: "1px solid oklch(0.70 0.19 28 / .35)", borderRadius: "var(--r-md)", padding: "12px 16px", fontSize: 14, color: "var(--hot)", marginBottom: 16 }}>
            {error}
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div className="field" style={{ gap: 7 }}>
            <label htmlFor="email" style={{ fontSize: 14, color: "var(--text-muted)", fontWeight: 600 }}>
              {t("email")}
            </label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              placeholder="seu@email.com"
              style={{
                border: "1.5px solid var(--border)", borderRadius: "var(--r-md)",
                background: "var(--bg-2)", padding: "14px 16px",
                fontFamily: "inherit", fontSize: 16, color: "var(--text)",
                outline: "none", width: "100%",
              }}
              onFocus={(e) => { e.target.style.borderColor = "var(--primary)"; }}
              onBlur={(e)  => { e.target.style.borderColor = "var(--border)"; }}
            />
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <label htmlFor="password" style={{ fontSize: 14, color: "var(--text-muted)", fontWeight: 600 }}>
                {t("password")}
              </label>
              <Link href="/forgot-password" style={{ fontSize: 13, color: "var(--primary)", fontWeight: 600, textDecoration: "none" }}>
                {t("forgotPassword")}
              </Link>
            </div>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              placeholder="••••••••"
              style={{
                border: "1.5px solid var(--border)", borderRadius: "var(--r-md)",
                background: "var(--bg-2)", padding: "14px 16px",
                fontFamily: "inherit", fontSize: 16, color: "var(--text)",
                outline: "none", width: "100%",
              }}
              onFocus={(e) => { e.target.style.borderColor = "var(--primary)"; }}
              onBlur={(e)  => { e.target.style.borderColor = "var(--border)"; }}
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            style={{
              marginTop: 6, width: "100%", borderRadius: "var(--r-pill)",
              padding: "16px", fontWeight: 700, fontSize: 16, border: 0,
              cursor: loading ? "not-allowed" : "pointer",
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)",
              boxShadow: "var(--glow)",
              opacity: loading ? 0.65 : 1,
              transition: "opacity .15s, transform .12s",
            }}
          >
            {loading ? t("signingIn") : t("signIn")}
          </button>
        </form>

        <p style={{ marginTop: 24, textAlign: "center", fontSize: 14, color: "var(--text-muted)" }}>
          {t("noAccount")}{" "}
          <Link href="/sign-up" style={{ color: "var(--primary)", fontWeight: 700, textDecoration: "none" }}>
            {t("signUp")}
          </Link>
        </p>
      </div>
    </div>
  );
}
