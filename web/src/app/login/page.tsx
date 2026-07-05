"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { getPendingPlan, clearPendingPlan } from "@/features/billing/checkout-intent";
import { trackCheckoutStarted } from "@/shared/lib/analytics";
import { Capacitor } from "@capacitor/core";

const OAUTH_ERROR_MESSAGE_KEYS: Record<string, string> = {
  account_deleted: "accountDeletedError",
  oauth_failed: "oauthError",
};

export default function LoginPage() {
  const { signIn } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const t = useTranslations("auth");
  const oauthErrorCode = searchParams.get("error");
  const [email, setEmail]       = useState("");
  const [password, setPassword] = useState("");
  const [error, setError]       = useState(
    oauthErrorCode ? t(OAUTH_ERROR_MESSAGE_KEYS[oauthErrorCode] ?? "loginError") : ""
  );
  const [loading, setLoading]   = useState(false);

  async function handleGoogleAuth(e: React.MouseEvent<HTMLAnchorElement>) {
    if (!Capacitor.isNativePlatform()) return;
    e.preventDefault();
    const { Browser } = await import("@capacitor/browser");
    const url = `${process.env.NEXT_PUBLIC_API_URL}/users/auth/google_oauth2?mobile=1`;
    await Browser.open({ url });
  }

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await signIn(email, password);
      const pending = getPendingPlan();
      if (pending) {
        clearPendingPlan();
        trackCheckoutStarted(pending, "login_pending_plan");
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

        {/* Google OAuth */}
        <a
          href={`${process.env.NEXT_PUBLIC_API_URL}/users/auth/google_oauth2`}
          onClick={handleGoogleAuth}
          style={{
            display: "flex", alignItems: "center", justifyContent: "center", gap: 12,
            width: "100%", padding: "14px 16px", borderRadius: "var(--r-pill)",
            border: "1.5px solid var(--border)", background: "var(--bg-2)",
            fontSize: 15, fontWeight: 600, color: "var(--text)",
            textDecoration: "none", marginBottom: 20, transition: "background .15s",
          }}
        >
          <svg width="18" height="18" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M47.532 24.552c0-1.636-.143-3.2-.41-4.704H24.48v8.892h12.968c-.56 2.996-2.24 5.54-4.768 7.252v6.02h7.716c4.516-4.16 7.136-10.284 7.136-17.46z" fill="#4285F4"/>
            <path d="M24.48 48c6.48 0 11.916-2.148 15.888-5.82l-7.716-6.02c-2.148 1.44-4.896 2.292-8.172 2.292-6.288 0-11.616-4.244-13.524-9.948H3.048v6.216C6.996 42.636 15.156 48 24.48 48z" fill="#34A853"/>
            <path d="M10.956 28.504A14.51 14.51 0 0 1 10.2 24c0-1.568.264-3.088.756-4.504v-6.216H3.048A23.98 23.98 0 0 0 .48 24c0 3.876.924 7.536 2.568 10.72l7.908-6.216z" fill="#FBBC05"/>
            <path d="M24.48 9.548c3.54 0 6.72 1.216 9.22 3.604l6.908-6.908C36.384 2.4 30.948 0 24.48 0 15.156 0 6.996 5.364 3.048 13.28l7.908 6.216c1.908-5.704 7.236-9.948 13.524-9.948z" fill="#EA4335"/>
          </svg>
          Continuar com Google
        </a>

        <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 20 }}>
          <div style={{ flex: 1, height: 1, background: "var(--border)" }} />
          <span style={{ fontSize: 12, color: "var(--text-muted)", opacity: 0.6 }}>ou</span>
          <div style={{ flex: 1, height: 1, background: "var(--border)" }} />
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
