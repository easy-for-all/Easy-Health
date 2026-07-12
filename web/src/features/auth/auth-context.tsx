"use client";

import { createContext, useContext, useEffect, useRef, useState, ReactNode } from "react";
import { api, ApiError, TRIAL_EXPIRED_EVENT } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";
import { Capacitor } from "@capacitor/core";

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
    const publicPaths = ["/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password", "/reset-password", "/billing/success", "/billing/cancel", "/pricing", "/s/", "/join/", "/delete-account", "/delete-data"];

    api.get<User>("/api/v1/auth/me")
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

        document.cookie = "_easy_health_session=; Max-Age=0; path=/; SameSite=Lax";
        if (window.location.hostname === "easyhealth.art" || window.location.hostname.endsWith(".easyhealth.art")) {
          document.cookie = "_eh_auth=; Max-Age=0; path=/; domain=.easyhealth.art; SameSite=Lax";
        }
        setUser(null);

        const pathname = window.location.pathname;
        if (!publicPaths.some((p) => (p === "/" ? pathname === "/" : pathname.startsWith(p)))) {
          window.location.replace("/login");
        }
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    if (!user) return;
    if (!Capacitor.isNativePlatform()) return;

    // Only re-syncs the token if the user already granted permission — never
    // prompts on login. The native prompt is shown only via the contextual
    // pre-permission opt-in after a workout is created.
    import("@/shared/lib/pushNotifications").then(({ syncPushIfGranted }) => {
      syncPushIfGranted().catch((err) => {
        console.error("[Push] Sync failed", err);
      });
    });
  }, [user?.id]);

  async function signIn(email: string, password: string) {
    const u = await api.post<User>("/api/v1/auth/sign_in", { email, password });
    setUser(u);
    justAuthenticatedRef.current = true;
  }

  async function signUp(name: string, email: string, password: string, marketingConsent?: boolean) {
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
      setUser(null);
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
