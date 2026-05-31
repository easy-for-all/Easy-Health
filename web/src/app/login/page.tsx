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
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

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
        router.push("/profile");
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else if (err instanceof TypeError) {
        setError("Não foi possível conectar ao servidor. Tente novamente.");
      } else {
        setError(t("loginError"));
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4" style={{ background: "#0a0f1e" }}>
      <div className="w-full max-w-sm">
        {/* Brand */}
        <div className="mb-8 flex flex-col items-center gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="EasyHealth" className="h-10 w-auto" />
          <span className="text-xl font-extrabold tracking-tight text-white">EasyHealth</span>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <p className="rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-400">{error}</p>
          )}

          <div>
            <label htmlFor="email" className="mb-1 block text-sm font-medium text-slate-400">{t("email")}</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              placeholder="seu@email.com"
            />
          </div>

          <div>
            <label htmlFor="password" className="mb-1 block text-sm font-medium text-slate-400">{t("password")}</label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              placeholder="••••••••"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 20px rgba(59,130,246,.28)" }}
          >
            {loading ? t("signingIn") : t("signIn")}
          </button>

          <p className="text-center">
            <Link href="/forgot-password" className="text-sm text-primary-400 hover:underline">
              {t("forgotPassword")}
            </Link>
          </p>
        </form>

        <p className="mt-6 text-center text-sm text-slate-500">
          {t("noAccount")}{" "}
          <Link href="/sign-up" className="font-medium text-primary-400 hover:underline">
            {t("signUp")}
          </Link>
        </p>
      </div>
    </div>
  );
}
