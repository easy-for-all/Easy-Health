"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { getPendingPlan, clearPendingPlan, type PendingPlan } from "@/features/billing/checkout-intent";
import { trackCheckoutStarted, trackEvent, EVENTS, trackConversion, CONVERSIONS } from "@/shared/lib/analytics";

const PLAN_COPY: Record<PendingPlan, {
  label: string;
  price: string;
  note: string;
}> = {
  pro_monthly: {
    label: "Pro Mensal",
    price: "R$ 19,90/mês",
    note: "7 dias grátis antes da cobrança",
  },
  pro_yearly: {
    label: "Pro Anual",
    price: "R$ 118,80/ano",
    note: "Equivale a R$ 9,90/mês",
  },
};

export default function SignUpPage() {
  const { signUp } = useAuth();
  const router = useRouter();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [pendingPlan] = useState<PendingPlan | null>(() => getPendingPlan());

  useEffect(() => {
    trackEvent(EVENTS.SIGNUP_STARTED);
  }, []);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await signUp(name, email, password);
      trackEvent(EVENTS.SIGNUP_COMPLETED);
      trackConversion(CONVERSIONS.SIGNUP);
      const pending = getPendingPlan();
      if (pending) {
        clearPendingPlan();
        trackCheckoutStarted(pending, "signup_pending_plan");
        const { checkout_url } = await api.post<{ checkout_url: string }>(
          "/api/v1/billing/checkout",
          { plan: pending }
        );
        window.location.href = checkout_url;
      } else {
        router.push("/onboarding");
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else if (err instanceof TypeError) {
        setError("Não foi possível conectar ao servidor. Tente novamente.");
      } else {
        setError("Erro ao criar conta");
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-svh items-center justify-center px-4 py-5" style={{ background: "#0a0f1e" }}>
      <div className="w-full max-w-sm">
        {/* Brand */}
        <div className="mb-5 flex flex-col items-center gap-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="EasyHealth" className="h-9 w-auto" />
          <div className="text-center">
            <h1 className="text-xl font-extrabold tracking-tight text-white">Criar conta</h1>
            <p className="mt-1 text-sm text-slate-400">Treino personalizado em poucos minutos</p>
          </div>
        </div>

        {pendingPlan && (
          <div className="mb-4 rounded-2xl border border-primary-500/30 bg-primary-500/10 px-4 py-3">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-white">{PLAN_COPY[pendingPlan].label}</p>
                <p className="mt-0.5 text-xs text-slate-300">{PLAN_COPY[pendingPlan].note}</p>
              </div>
              <p className="shrink-0 text-right text-sm font-bold text-primary-300">{PLAN_COPY[pendingPlan].price}</p>
            </div>
            <div className="mt-3 grid grid-cols-3 gap-2 text-center text-[11px] font-medium text-slate-300">
              <span className="rounded-full bg-slate-900/70 px-2 py-1">IA</span>
              <span className="rounded-full bg-slate-900/70 px-2 py-1">Histórico</span>
              <span className="rounded-full bg-slate-900/70 px-2 py-1">Coach</span>
            </div>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <p className="rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-400">{error}</p>
          )}

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-400">Nome</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              minLength={2}
              className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              placeholder="Seu nome"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-400">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              placeholder="seu@email.com"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-400">Senha</label>
            <input
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
              placeholder="Mínimo 8 caracteres"
            />
          </div>

          <label className="flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={acceptedTerms}
              onChange={(e) => setAcceptedTerms(e.target.checked)}
              className="mt-0.5 h-4 w-4 flex-shrink-0 rounded border-slate-600 text-primary-500 focus:ring-primary-500"
            />
            <span className="text-sm text-slate-400">
              Li e concordo com os{" "}
              <a href="/terms" target="_blank" rel="noopener noreferrer" className="font-medium text-primary-400 hover:underline">
                Termos de Uso
              </a>{" "}
              e a{" "}
              <a href="/privacy" target="_blank" rel="noopener noreferrer" className="font-medium text-primary-400 hover:underline">
                Política de Privacidade
              </a>
            </span>
          </label>

          <button
            type="submit"
            disabled={loading || !acceptedTerms}
            className="w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 20px rgba(59,130,246,.28)" }}
          >
            {loading ? "Criando conta..." : "Criar conta"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-slate-500">
          Já tem conta?{" "}
          <Link href="/login" className="font-medium text-primary-400 hover:underline">
            Entrar
          </Link>
        </p>
      </div>
    </div>
  );
}
