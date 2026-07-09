"use client";

import { createContext, useContext, useEffect, useRef, useState, ReactNode } from "react";
import { api, ApiError, TRIAL_EXPIRED_EVENT } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";
import { Capacitor } from "@capacitor/core";
import { exchangeMobileAuthCallback, parseMobileAuthCallback } from "@/shared/lib/mobileAuth";

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
    if (!Capacitor.isNativePlatform()) return;

    let cleanup: (() => void) | undefined;
    import("@capacitor/app").then(({ App }) => {
      const listenerPromise = App.addListener("appUrlOpen", async (event) => {
        const parsed = parseMobileAuthCallback(event.url);
        if (!parsed) return;

        try {
          const { Browser } = await import("@capacitor/browser");
          await Browser.close().catch(() => undefined);
          const result = await exchangeMobileAuthCallback(parsed);
          setUser(result.user);
          justAuthenticatedRef.current = true;
          window.location.replace(result.redirectPath);
        } catch {
          window.location.replace("/login?error=oauth_failed");
        }
      });
      cleanup = () => { listenerPromise.then((l) => l.remove()); };
    });

    return () => cleanup?.();
  }, []);

  useEffect(() => {
    const publicPaths = ["/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password", "/reset-password", "/billing/success", "/billing/cancel", "/pricing", "/mobile-auth/callback", "/s/", "/join/", "/delete-account", "/delete-data"];

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

    import("@/shared/lib/pushNotifications").then(({ initPushNotifications }) => {
      initPushNotifications().catch((err) => {
        console.error("[Push] Init failed", err);
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
