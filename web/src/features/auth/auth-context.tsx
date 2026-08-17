"use client";

import { createContext, useContext, useEffect, useRef, useState, ReactNode } from "react";
import { api, ApiError, TRIAL_EXPIRED_EVENT } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";
import { isNativeApp } from "@/shared/lib/analytics/context";
import { identifyUser, resetIdentity } from "@/shared/lib/analytics";
import { ensureInstallationForAuth } from "@/shared/lib/analytics/installation";
import { navigateInternal } from "@/shared/lib/app-navigation";
import {
  captureMobileSessionToken,
  clearMobileSessionToken,
  primeMobileSessionToken,
} from "@/shared/lib/mobile-session";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (name: string, email: string, password: string, marketingConsent?: boolean) => Promise<void>;
  signOut: () => Promise<void>;
  updateUser: (patch: Partial<User>) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const justAuthenticatedRef = useRef(false);

  useEffect(() => {
    // Mantida alinhada com PUBLIC_PATHS em proxy.ts. /native-entry e /onboarding
    // faltavam aqui: a borda já os liberava, mas este guard mandava o visitante
    // para /login mesmo assim — e o onboarding do Android começa sem sessão.
    // Quem protege /onboarding na Web é a própria página, que redireciona quando
    // não é nativo e não há usuário.
    const publicPaths = ["/", "/login", "/sign-up", "/native-entry", "/onboarding", "/plano", "/terms", "/privacy", "/forgot-password", "/reset-password", "/billing/success", "/billing/cancel", "/pricing", "/s/", "/join/", "/delete-account", "/delete-data"];

    // O bearer token vive no Preferences (assíncrono) e api.ts monta headers de
    // forma síncrona. Carregar para memória ANTES da primeira requisição é o que
    // impede o app nativo de abrir sempre deslogado.
    primeMobileSessionToken()
      .then(() => api.get<User>("/api/v1/auth/me"))
      .then((u) => {
        if (justAuthenticatedRef.current) return;
        setUser(u);
      })
      .catch((error: unknown) => {
        if (justAuthenticatedRef.current) return;
        if (!(error instanceof ApiError && [401, 403].includes(error.status))) {
          setUser(null);
          return;
        }

        void api.delete("/api/v1/auth/sign_out").catch(() => undefined);
        void clearMobileSessionToken();

        document.cookie = "_easy_health_session=; Max-Age=0; path=/; SameSite=Lax";
        if (window.location.hostname === "easyhealth.art" || window.location.hostname.endsWith(".easyhealth.art")) {
          document.cookie = "_eh_auth=; Max-Age=0; path=/; domain=.easyhealth.art; SameSite=Lax";
        }
        setUser(null);

        const pathname = window.location.pathname;
        if (!publicPaths.some((p) => (p === "/" ? pathname === "/" : pathname.startsWith(p)))) {
          navigateInternal("/login", "replace");
        }
      })
      .finally(() => setLoading(false));
  }, []);

  // Associate the anonymous analytics thread with the authenticated user across
  // sinks (GA4 user_id, Clarity identify). anonymous_id is preserved.
  useEffect(() => {
    if (user?.id) identifyUser(user.id);
  }, [user?.id]);

  // Reivindica plano e treinos feitos antes da conta existir. Roda em toda
  // sessão resolvida, não só logo após o cadastro: um claim que não completou
  // (rede caiu, app foi fechado) deixa dado real preso na instalação, e a
  // próxima abertura é a única chance de recuperá-lo. É no-op quando não há
  // token anônimo — que é o caso da Web, do PWA e de quem nunca usou sem conta.
  useEffect(() => {
    if (!user?.id) return;

    import("@/features/anonymous/claim").then(({ claimAnonymousData }) => {
      void claimAnonymousData();
    });
  }, [user?.id]);

  useEffect(() => {
    if (!user) return;
    // isNativeApp(), never Capacitor.isNativePlatform(): the shell loads the
    // REMOTE site in a WebView, where isNativePlatform() can return false. This
    // gate was silently skipping the whole push sync on real Android devices
    // (see docs/android-tracking-audit.md).
    if (!isNativeApp()) return;

    // Runs once the session is ready (user resolved from /auth/me or a login).
    // Only re-syncs the token if the user already granted permission — never
    // prompts on login. Idempotent: concurrent invocations (incl. React Strict
    // Mode double-mount) share a single in-flight operation. A transient failure
    // here is retried, idempotently, on the next authenticated boot/login.
    import("@/shared/lib/pushNotifications").then(({ syncPushIfGranted }) => {
      syncPushIfGranted("auth_boot").catch((err) => {
        console.error("[Push] Sync failed", err);
      });
    });
  }, [user?.id]);

  // Email sign-in/sign-up used to authenticate before the installation_id had
  // resolved, so the very request that creates the session went out without
  // X-Installation-Id — unlike native Google login, which already waited for it.
  // Time-boxed and best-effort: tracking never blocks or breaks authentication.
  async function signIn(email: string, password: string) {
    await ensureInstallationForAuth();
    const u = await api.post<User>("/api/v1/auth/sign_in", { email, password });
    // Shell nativo com bundle local: guarda o bearer token antes de qualquer
    // requisição seguinte, que já dependerá dele.
    await captureMobileSessionToken(u);
    setUser(u);
    justAuthenticatedRef.current = true;
  }

  async function signUp(name: string, email: string, password: string, marketingConsent?: boolean) {
    await ensureInstallationForAuth();
    const u = await api.post<User>("/api/v1/auth/sign_up", {
      name,
      email,
      password,
      password_confirmation: password,
      // Reachable only after the sign-up screen's consent gate, so the required
      // Terms + Privacy acceptance is guaranteed here. The backend stamps the
      // authoritative versions/timestamps from these flags.
      terms_accepted: true,
      privacy_accepted: true,
      marketing_consent: marketingConsent ?? false,
    });
    await captureMobileSessionToken(u);
    setUser(u);
    justAuthenticatedRef.current = true;
  }

  async function signOut() {
    try {
      await api.delete("/api/v1/auth/sign_out");
    } catch {
      // server-side signout failed; local state still cleared in finally
    } finally {
      document.cookie = "_easy_health_session=; Max-Age=0; path=/; SameSite=Lax";
      // O servidor já revogou; isto tira o token do disco para o app não
      // reabrir tentando autenticar com credencial morta.
      await clearMobileSessionToken();
      setUser(null);
      resetIdentity();
    }
  }

  function updateUser(patch: Partial<User>) {
    setUser((prev) => prev ? { ...prev, ...patch } : prev);
  }

  useEffect(() => {
    function handleTrialExpired() {
      setUser((prev) => {
        if (!prev?.billing_status) return prev;
        return {
          ...prev,
          billing_status: {
            ...prev.billing_status,
            app_trial_active: false,
            app_trial_days_remaining: 0,
            access_locked: true,
          },
        };
      });
    }
    window.addEventListener(TRIAL_EXPIRED_EVENT, handleTrialExpired);
    return () => window.removeEventListener(TRIAL_EXPIRED_EVENT, handleTrialExpired);
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, signIn, signUp, signOut, updateUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
}
