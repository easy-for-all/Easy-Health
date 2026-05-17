"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { ApiError } from "@/shared/lib/api";

export default function ResetPasswordPage() {
  const t = useTranslations("auth");
  const router = useRouter();
  const params = useSearchParams();

  const token = params.get("token") ?? "";
  const email = params.get("email") ?? "";

  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError("");

    if (password.length < 8) {
      setError(t("passwordTooShort"));
      return;
    }
    if (password !== confirmation) {
      setError(t("passwordMismatch"));
      return;
    }

    setLoading(true);
    try {
      await api.post("/api/v1/auth/password/reset", {
        email,
        token,
        password,
        password_confirmation: confirmation,
      });
      setSuccess(true);
      setTimeout(() => router.push("/login"), 2500);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t("invalidToken"));
      }
    } finally {
      setLoading(false);
    }
  }

  if (!token || !email) {
    return (
      <div className="flex min-h-screen items-center justify-center px-4">
        <div className="w-full max-w-sm text-center">
          <p className="mb-4 text-sm text-red-600">{t("invalidToken")}</p>
          <Link href="/forgot-password" className="text-sm font-medium text-primary-600 hover:underline">
            {t("sendLink")}
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <h1 className="mb-2 text-center text-2xl font-bold text-gray-900">{t("resetTitle")}</h1>
        <p className="mb-8 text-center text-sm text-gray-500">{t("resetSubtitle")}</p>

        {success ? (
          <p className="rounded-lg bg-green-50 px-4 py-3 text-center text-sm text-green-700">
            {t("resetSuccess")}
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            {error && (
              <p className="rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
            )}

            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">{t("newPassword")}</label>
              <input
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={8}
                className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
                placeholder="Mínimo 8 caracteres"
              />
            </div>

            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">{t("confirmPassword")}</label>
              <input
                type="password"
                autoComplete="new-password"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
                required
                minLength={8}
                className="w-full rounded-lg border border-gray-300 px-4 py-3 text-sm focus:border-primary-500 focus:outline-none"
                placeholder="Repita a senha"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
            >
              {loading ? t("resettingButton") : t("resetButton")}
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
