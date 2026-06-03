"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useAuth } from "@/features/auth/auth-context";
import { api } from "@/shared/lib/api";

export default function PersonalOnboardingPage() {
  const t = useTranslations("personal");
  const router = useRouter();
  const { user, updateUser } = useAuth();
  const [loading, setLoading] = useState(false);

  if (user?.account_type === "personal_trainer") {
    router.replace("/personal/dashboard");
    return null;
  }

  async function handleActivate() {
    setLoading(true);
    try {
      const data = await api.post<{ account_type: string }>("/api/v1/personal/activate", {});
      updateUser({ account_type: data.account_type as "personal_trainer" });
      router.push("/personal/dashboard");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50 px-6 pb-24 dark:bg-gray-950">
      <div className="w-full max-w-sm space-y-6 text-center">
        <div className="text-5xl">💪</div>
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">{t("onboarding_title")}</h1>
          <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">{t("onboarding_subtitle")}</p>
        </div>

        <ul className="space-y-3 text-left">
          {[
            "Convide alunos por link",
            "Atribua planos de treino personalizados",
            "Acompanhe aderência e evolução",
            "Receba comissão por indicações (em breve)",
          ].map((item) => (
            <li key={item} className="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
              <span className="mt-0.5 text-primary-500">✓</span>
              {item}
            </li>
          ))}
        </ul>

        <button
          onClick={handleActivate}
          disabled={loading}
          className="w-full rounded-2xl bg-primary-500 py-3.5 text-sm font-semibold text-white transition-colors hover:bg-primary-600 disabled:opacity-50"
        >
          {loading ? t("activating") : t("activate")}
        </button>

        <button onClick={() => router.back()} className="text-sm text-gray-400 hover:text-gray-600">
          Agora não
        </button>
      </div>
    </div>
  );
}
