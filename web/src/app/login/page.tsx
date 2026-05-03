"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";

export default function LoginPage() {
  const { signIn } = useAuth();
  const router = useRouter();
  const t = useTranslations("auth");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await signIn(email, password);
      router.push("/profile");
    } catch (err) {
      setError(err instanceof Error ? err.message : t("loginError"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <h1 className="mb-8 text-center text-2xl font-bold text-gray-900">Easy Health</h1>

        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <p className="rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
          )}

          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">{t("email")}</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
              placeholder="seu@email.com"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">{t("password")}</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
              className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
              placeholder="••••••••"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
          >
            {loading ? t("signingIn") : t("signIn")}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-500">
          {t("noAccount")}{" "}
          <Link href="/sign-up" className="font-medium text-primary-600 hover:underline">
            {t("signUp")}
          </Link>
        </p>
      </div>
    </div>
  );
}
