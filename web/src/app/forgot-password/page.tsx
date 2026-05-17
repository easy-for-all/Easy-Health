"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";

export default function ForgotPasswordPage() {
  const t = useTranslations("auth");
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post("/api/v1/auth/password/forgot", { email });
    } finally {
      // Always show generic message regardless of result
      setSent(true);
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <h1 className="mb-2 text-center text-2xl font-bold text-gray-900">{t("forgotTitle")}</h1>
        <p className="mb-8 text-center text-sm text-gray-500">{t("forgotSubtitle")}</p>

        {sent ? (
          <div className="space-y-4 text-center">
            <p className="rounded-lg bg-green-50 px-4 py-3 text-sm text-green-700">
              {t("forgotSuccess")}
            </p>
            <Link href="/login" className="block text-sm font-medium text-primary-600 hover:underline">
              {t("backToLogin")}
            </Link>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">{t("email")}</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
                placeholder="seu@email.com"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
            >
              {loading ? t("sendingLink") : t("sendLink")}
            </button>

            <p className="text-center">
              <Link href="/login" className="text-sm text-gray-500 hover:underline">
                {t("backToLogin")}
              </Link>
            </p>
          </form>
        )}
      </div>
    </div>
  );
}
