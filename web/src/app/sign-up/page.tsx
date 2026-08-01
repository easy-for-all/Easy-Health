"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/features/auth/auth-context";
import { api, ApiError } from "@/shared/lib/api";
import { checkoutErrorCode, checkoutErrorMessage, reportCheckoutException } from "@/features/billing/checkout-errors";
import { getPendingPlan, clearPendingPlan, type PendingPlan } from "@/features/billing/checkout-intent";
import { checkoutEventParams, trackCheckoutStarted, trackEvent, EVENTS, trackConversion, CONVERSIONS } from "@/shared/lib/analytics";
import {
  reportAuthError,
  trackAuthApiError,
  trackAuthClientError,
  trackAuthProviderClicked,
  trackLoginSelected,
  useAuthScreenView,
} from "@/features/auth/auth-analytics";
import { useIsHydrated, useIsNativePlatform } from "@/shared/lib/platform";
import {
  GoogleAuthError,
  authLog,
  classifyGoogleAuthError,
  startGoogleAuth,
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

type CheckoutResponse = { checkout_url: string; session_id?: string };

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
  const googleRef = useRef(false);
  const consentCheckboxRef = useRef<HTMLInputElement>(null);
  const hydrated = useIsHydrated();
  const isNative = useIsNativePlatform();

  useAuthScreenView("sign_up");
  // Arriving from the login screen's "create account with Google" CTA. Only
  // highlights the Google option — it never pre-accepts anything nor starts OAuth.
  const fromGoogle = searchParams.get("provider") === "google";
  const consentRefused = searchParams.get("error") === "consent_required";
  // Derived rather than stored: a refused social sign-in must surface the same
  // warning as a blocked submit, without a setState-in-effect round trip.
  //
  // Suppressed while the banner above is on screen: that banner already says to
  // accept the terms, in the same words and in the same place, and showing both
  // stacks two identical alerts on top of each other.
  const consentBannerShown = fromGoogle || consentRefused;
  const showTermsWarning = (termsWarning || consentRefused) && !acceptedTerms && !consentBannerShown;

  const passwordValid = password.length >= 8;
  // Single checkbox covers both Terms of Use and Privacy Policy.
  const consent: GoogleConsent = {
    termsAccepted: acceptedTerms,
    privacyAccepted: acceptedTerms,
    marketingConsent,
  };

  async function handleGoogleAuth(e: React.MouseEvent<HTMLButtonElement>) {
    e.preventDefault();
    e.stopPropagation();

    if (googleRef.current) return;
    trackAuthProviderClicked({
      provider: "google",
      authScreen: "sign_up",
      intent: "sign_up",
      termsAccepted: acceptedTerms,
    });

    // Defense in depth: block the social flow before ANY side effect when the
    // required consent is missing — same gate as the email/password submit.
    if (!acceptedTerms) {
      setTermsWarning(true);
      consentCheckboxRef.current?.focus();
      authLog("auth_blocked_missing_consent", {
        provider: "google",
        surface: "signup",
        platform: isNative ? "android" : "web",
        missing_terms: true,
        missing_privacy: true,
      });
      return;
    }

    googleRef.current = true;

    setError("");
    setGoogleLoading(true);
    trackEvent("social_login_started", { provider: "google", intent: "sign_up" });
    try {
      const outcome = await startGoogleAuth({ native: isNative, consent });
      if (outcome.navigated) return; // leaving the page; keep the loading state
      window.location.replace(outcome.redirectPath);
    } catch (err) {
      googleRef.current = false;
      setGoogleLoading(false);
      const code = err instanceof GoogleAuthError ? err.code : "unknown";
      const failure = classifyGoogleAuthError(err);
      authLog("signup_failed", {
        code,
        failure,
        name: (err as Error)?.name,
        message: (err as Error)?.message,
      });
      // Same split as the login screen: did it die on the device, or did the API
      // answer? That is the distinction the funnel could not make at all.
      const reachedApi = failure === "network" || code === "exchange_failed" ||
        ["consent_required", "account_deleted", "invalid_token"].includes(code);
      if (reachedApi) {
        trackAuthApiError("google_exchange", err, "google");
      } else {
        trackEvent("social_login_failed", { provider: "google", error_code: failure });
        trackAuthClientError("google_plugin", code, "google");
      }
      if (failure !== "cancelled" && failure !== "consent_required") {
        reportAuthError("google_plugin", err, { failure, code });
      }

      switch (failure) {
        case "consent_required":
          setTermsWarning(true);
          consentCheckboxRef.current?.focus();
          setError("Aceite os Termos de Uso e a Política de Privacidade para criar sua conta.");
          break;
        case "cancelled":
          break; // the user chose to back out — not an error to report
        case "account_deleted":
          setError("Esta conta foi excluída e não pode ser reativada.");
          break;
        case "network":
          setError("Não foi possível conectar ao servidor. Tente novamente.");
          break;
        default:
          setError("Não foi possível entrar com o Google. Tente novamente.");
      }
    }
  }

  // signup_started used to fire here, on mount, which made it a screen view
  // wearing an intent name. auth_screen_viewed (useAuthScreenView above) is the
  // screen view now, and signup_started moved to the actual submit so it is
  // symmetric with login_started and countable against signup_completed.

  // A social sign-in that was refused for missing consent lands here; the
  // warning is derived above, so this effect only moves focus (a real DOM side
  // effect). The checkbox itself is never pre-checked.
  useEffect(() => {
    if (consentRefused) consentCheckboxRef.current?.focus();
  }, [consentRefused]);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (submittingRef.current) return;
    trackAuthProviderClicked({
      provider: "email",
      authScreen: "sign_up",
      intent: "sign_up",
      termsAccepted: acceptedTerms,
    });
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
    // Past every client-side gate, before the request leaves.
    trackEvent(EVENTS.SIGNUP_STARTED, { method: "email" });
    try {
      await signUp(submittedName, submittedEmail, submittedPassword, marketingConsent);
      trackEvent(EVENTS.SIGNUP_COMPLETED);
      trackConversion(CONVERSIONS.SIGNUP);
      const pending = getPendingPlan();
      if (pending) {
        trackCheckoutStarted(pending, "signup_pending_plan");
        try {
          const { checkout_url, session_id } = await api.post<CheckoutResponse>(
            "/api/v1/billing/checkout",
            { plan: pending }
          );
          clearPendingPlan();
          trackEvent(EVENTS.CHECKOUT_SESSION_CREATED, {
            ...checkoutEventParams(pending, "signup_pending_plan"),
            session_id,
          });
          trackEvent(EVENTS.CHECKOUT_REDIRECT_OPENED, checkoutEventParams(pending, "signup_pending_plan"));
          window.location.href = checkout_url;
        } catch (checkoutError) {
          reportCheckoutException(checkoutError, { plan: pending, source: "signup_pending_plan" });
          trackEvent(EVENTS.CHECKOUT_FAILED, {
            ...checkoutEventParams(pending, "signup_pending_plan"),
            error_code: checkoutErrorCode(checkoutError),
          });
          setError(checkoutErrorMessage(checkoutError));
        }
      } else {
        router.push("/onboarding");
      }
    } catch (err) {
      if (err instanceof ApiError) {
        trackAuthApiError("email_signup", err);
        setError(err.message);
      } else if (err instanceof TypeError) {
        // fetch itself rejected: the request never got an answer.
        trackAuthClientError("email_signup", "network");
        setError("Não foi possível conectar ao servidor. Tente novamente.");
      } else {
        trackAuthClientError("email_signup", "unknown");
        reportAuthError("email_signup", err);
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

        {/* Came from the login screen's "create account with Google" CTA. */}
        {(fromGoogle || consentRefused) && (
          <p className="mb-3 rounded-xl border border-amber-800/60 bg-amber-950/30 px-4 py-3 text-sm text-amber-300">
            {consentRefused
              ? "Para criar sua conta com o Google, aceite os Termos de Uso e a Política de Privacidade abaixo e tente novamente."
              : "Esta conta Google ainda não está cadastrada. Aceite os Termos de Uso e a Política de Privacidade abaixo para criar sua conta."}
          </p>
        )}

        {/* The consent warning has to sit HERE, immediately above the button that
            triggered it. It used to render only at the bottom of the form, ~400px
            down and off-screen on a phone, so tapping the greyed-out Google
            button looked like it simply did nothing. */}
        {showTermsWarning && (
          <p
            role="alert"
            className="mb-3 rounded-xl border border-amber-800/60 bg-amber-950/30 px-4 py-3 text-sm text-amber-300"
          >
            Aceite os Termos de Uso e a Política de Privacidade abaixo para continuar.
          </p>
        )}

        {/* Google OAuth — a <button>, never an <a href>: the server-rendered
            markup must not carry a working OAuth link, and the consent params
            now travel through an explicit navigation instead of an attribute. */}
        <button
          type="button"
          onClick={handleGoogleAuth}
          disabled={!hydrated || googleLoading}
          aria-busy={googleLoading}
          aria-disabled={!acceptedTerms}
          className={`flex w-full items-center justify-center gap-3 rounded-full border py-3 text-sm font-semibold text-white transition ${
            acceptedTerms && hydrated
              ? "border-slate-700 bg-slate-900 hover:bg-slate-800"
              : "cursor-not-allowed border-slate-700 bg-slate-900 opacity-50"
          } ${fromGoogle ? "ring-2 ring-primary-500/60" : ""}`}
        >
          <svg width="18" height="18" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M47.532 24.552c0-1.636-.143-3.2-.41-4.704H24.48v8.892h12.968c-.56 2.996-2.24 5.54-4.768 7.252v6.02h7.716c4.516-4.16 7.136-10.284 7.136-17.46z" fill="#4285F4"/>
            <path d="M24.48 48c6.48 0 11.916-2.148 15.888-5.82l-7.716-6.02c-2.148 1.44-4.896 2.292-8.172 2.292-6.288 0-11.616-4.244-13.524-9.948H3.048v6.216C6.996 42.636 15.156 48 24.48 48z" fill="#34A853"/>
            <path d="M10.956 28.504A14.51 14.51 0 0 1 10.2 24c0-1.568.264-3.088.756-4.504v-6.216H3.048A23.98 23.98 0 0 0 .48 24c0 3.876.924 7.536 2.568 10.72l7.908-6.216z" fill="#FBBC05"/>
            <path d="M24.48 9.548c3.54 0 6.72 1.216 9.22 3.604l6.908-6.908C36.384 2.4 30.948 0 24.48 0 15.156 0 6.996 5.364 3.048 13.28l7.908 6.216c1.908-5.704 7.236-9.948 13.524-9.948z" fill="#EA4335"/>
          </svg>
          {!hydrated ? "Carregando..." : googleLoading ? "Entrando com Google..." : "Continuar com Google"}
        </button>

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
          {showTermsWarning && (
            <p className="text-center text-xs text-amber-400">Aceite os termos para continuar</p>
          )}
        </form>

        <p className="mt-6 text-center text-sm text-slate-500">
          Já tem conta?{" "}
          <Link
            href="/login"
            onClick={() => trackLoginSelected("sign_up")}
            className="font-medium text-primary-400 hover:underline"
          >
            Entrar
          </Link>
        </p>
      </div>
    </div>
  );
}
