"use client";

import { createContext, useContext, useEffect, useState, ReactNode } from "react";
import { api, ApiError } from "@/shared/lib/api";
import type { User } from "@/shared/types/user";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (name: string, email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  updateUser: (patch: Partial<User>) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const publicPaths = ["/", "/login", "/sign-up", "/terms", "/privacy", "/forgot-password", "/reset-password", "/billing/success", "/billing/cancel", "/pricing", "/s/", "/join/"];

    api.get<User>("/api/v1/auth/me")
      .then(setUser)
      .catch((error: unknown) => {
        if (error instanceof ApiError && [401, 403].includes(error.status)) {
          void api.delete("/api/v1/auth/sign_out").catch(() => undefined);
        }

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

  async function signIn(email: string, password: string) {
    const u = await api.post<User>("/api/v1/auth/sign_in", { email, password });
    setUser(u);
  }

  async function signUp(name: string, email: string, password: string) {
    const u = await api.post<User>("/api/v1/auth/sign_up", {
      name,
      email,
      password,
      password_confirmation: password,
    });
    setUser(u);
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
