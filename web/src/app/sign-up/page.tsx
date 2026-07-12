"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { getPendingPlan, clearPendingPlan, type PendingPlan } from "@/features/billing/checkout-intent";
import { trackCheckoutStarted, trackEvent, EVENTS, trackConversion, CONVERSIONS } from "@/shared/lib/analytics";
import { Capacitor } from "@capacitor/core";
import {
  googleAuthWebUrl,
  GoogleAuthError,
  authLog,
  nativeGoogleSignIn,
  postGoogleNative,
  type GoogleConsent,
} from "@/shared/lib/googleAuth";

function EyeIcon({ open }: { open: boolean }) {
  return open ? (
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  ) : (
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}

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
  const searchParams = useSearchParams();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [termsWarning, setTermsWarning] = useState(false);
  const [marketingConsent, setMarketingConsent] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [pendingPlan] = useState<PendingPlan | null>(() => getPendingPlan());
  const submittingRef = useRef(false);
  const consentCheckboxRef = useRef<HTMLInputElement>(null);

  const passwordValid = password.length >= 8;
  // Single checkbox covers both Terms of Use and Privacy Policy.
  const consent: GoogleConsent = {
    termsAccepted: acceptedTerms,
    privacyAccepted: acceptedTerms,
    marketingConsent,
  };

  async function handleGoogleAuth(e: React.MouseEvent<HTMLAnchorElement>) {
    // Defense in depth: block the social flow before ANY side effect when the
    // required consent is missing — same gate as the email/password submit.
    if (!acceptedTerms) {
      e.preventDefault();
      setTermsWarning(true);
      consentCheckboxRef.current?.focus();
      authLog("auth_blocked_missing_consent", {
        provider: "google",
        surface: "signup",
        platform: Capacitor.isNativePlatform() ? "android" : "web",
        missing_terms: true,
        missing_privacy: true,
      });
      return;
    }

    // Web keeps the server-side OmniAuth flow (follows the <a href>, which
    // already carries the consent query params).
    if (!Capacitor.isNativePlatform()) return;
    // Android uses native Google Sign-In (no browser, no intermediate screen).
    e.preventDefault();
    setError("");
    setGoogleLoading(true);
    try {
      const idToken = await nativeGoogleSignIn();
      const { redirectPath } = await postGoogleNative(idToken, consent);
      window.location.replace(redirectPath);
    } catch (err) {
      setGoogleLoading(false);
      const code = err instanceof GoogleAuthError ? err.code : "unknown";
      authLog("signup_failed", {
        code,
        name: (err as Error)?.name,
        message: (err as Error)?.message,
      });
      setError(`Não foi possível entrar com Google. (${code})`);
    }
  }

  useEffect(() => {
    trackEvent(EVENTS.SIGNUP_STARTED);
  }, []);

  // A social sign-in that was refused for missing consent lands here; highlight
  // the same checkbox the email/password flow uses.
  useEffect(() => {
    if (searchParams.get("error") === "consent_required") {
      setTermsWarning(true);
      consentCheckboxRef.current?.focus();
    }
  }, [searchParams]);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (submittingRef.current) return;
    const formData = new FormData(e.currentTarget);
    const submittedName = String(formData.get("name") ?? "").trim();
    const submittedEmail = String(formData.get("email") ?? "").trim();
    const submittedPassword = String(formData.get("password") ?? "");

    if (!acceptedTerms) {
      setTermsWarning(true);
      return;
    }

    if (!submittedName || !submittedEmail || !submittedPassword) {
      setError("Preencha todos os campos para continuar.");
      return;
    }

    if (submittedPassword.length < 8) {
      setError("A senha deve ter pelo menos 8 caracteres.");
      return;
    }

    setError("");
    setLoading(true);
    submittingRef.current = true;
    try {
      await signUp(submittedName, submittedEmail, submittedPassword, marketingConsent);
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
      submittingRef.current = false;
      setLoading(false);
    }
  }

  return (
    <div
      className="flex min-h-svh items-center justify-center"
      style={{
        background: "#0a0f1e",
        paddingTop: "max(20px, var(--safe-area-top))",
        paddingRight: "max(16px, var(--safe-area-right))",
        paddingBottom: "max(20px, var(--safe-area-bottom))",
        paddingLeft: "max(16px, var(--safe-area-left))",
      }}
    >
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

        {/* Google OAuth */}
        <a
          href={acceptedTerms ? googleAuthWebUrl(consent) : undefined}
          onClick={handleGoogleAuth}
          aria-busy={googleLoading}
          aria-disabled={!acceptedTerms}
          className={`flex w-full items-center justify-center gap-3 rounded-full border border-slate-700 bg-slate-900 py-3 text-sm font-semibold text-white transition ${acceptedTerms ? "hover:bg-slate-800" : "cursor-not-allowed opacity-50"}`}
        >
          <svg width="18" height="18" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M47.532 24.552c0-1.636-.143-3.2-.41-4.704H24.48v8.892h12.968c-.56 2.996-2.24 5.54-4.768 7.252v6.02h7.716c4.516-4.16 7.136-10.284 7.136-17.46z" fill="#4285F4"/>
            <path d="M24.48 48c6.48 0 11.916-2.148 15.888-5.82l-7.716-6.02c-2.148 1.44-4.896 2.292-8.172 2.292-6.288 0-11.616-4.244-13.524-9.948H3.048v6.216C6.996 42.636 15.156 48 24.48 48z" fill="#34A853"/>
            <path d="M10.956 28.504A14.51 14.51 0 0 1 10.2 24c0-1.568.264-3.088.756-4.504v-6.216H3.048A23.98 23.98 0 0 0 .48 24c0 3.876.924 7.536 2.568 10.72l7.908-6.216z" fill="#FBBC05"/>
            <path d="M24.48 9.548c3.54 0 6.72 1.216 9.22 3.604l6.908-6.908C36.384 2.4 30.948 0 24.48 0 15.156 0 6.996 5.364 3.048 13.28l7.908 6.216c1.908-5.704 7.236-9.948 13.524-9.948z" fill="#EA4335"/>
          </svg>
          {googleLoading ? "Entrando com Google..." : "Continuar com Google"}
        </a>

        <div className="flex items-center gap-3">
          <div className="h-px flex-1 bg-slate-800" />
          <span className="text-xs text-slate-600">ou</span>
          <div className="h-px flex-1 bg-slate-800" />
        </div>

        <form noValidate onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <p className="rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-400">{error}</p>
          )}

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-400">Nome</label>
            <input
              name="name"
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
              name="email"
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
            <div className="relative">
              <input
                name="password"
                type={showPassword ? "text" : "password"}
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={8}
                className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 pr-11 text-sm text-white placeholder-slate-500 focus:border-primary-500 focus:outline-none"
                placeholder="Mínimo 8 caracteres"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300 transition"
                tabIndex={-1}
                aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
              >
                <EyeIcon open={showPassword} />
              </button>
            </div>
            {password.length > 0 && (
              <p className={`mt-1.5 text-xs ${passwordValid ? "text-green-400" : "text-slate-500"}`}>
                {passwordValid ? "✓" : "✗"} Mínimo 8 caracteres
              </p>
            )}
          </div>

          <label className="flex cursor-pointer items-start gap-3">
            <input
              ref={consentCheckboxRef}
              type="checkbox"
              checked={acceptedTerms}
              onChange={(e) => { setAcceptedTerms(e.target.checked); if (e.target.checked) setTermsWarning(false); }}
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

          <label className="flex cursor-pointer items-start gap-3">
            <input
              type="checkbox"
              checked={marketingConsent}
              onChange={(e) => setMarketingConsent(e.target.checked)}
              className="mt-0.5 h-4 w-4 flex-shrink-0 rounded border-slate-600 text-primary-500 focus:ring-primary-500"
            />
            <span className="text-sm text-slate-400">
              Aceito receber dicas personalizadas, lembretes de treino e novidades da EasyHealth por e-mail
            </span>
          </label>

          <button
            type="submit"
            disabled={loading}
            onClick={() => { if (!acceptedTerms) setTermsWarning(true); }}
            className="w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
            style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 20px rgba(59,130,246,.28)" }}
          >
            {loading ? "Criando conta..." : "Criar conta"}
          </button>
          {termsWarning && !acceptedTerms && (
            <p className="text-center text-xs text-amber-400">Aceite os termos para continuar</p>
          )}
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
