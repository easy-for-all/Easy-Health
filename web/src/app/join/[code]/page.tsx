"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { api } from "@/shared/lib/api";
import { useAuth } from "@/features/auth/auth-context";

type AcceptResult = {
  message: string;
  personal_name: string;
  relationship_id: number;
};

export default function JoinPage() {
  const params = useParams();
  const router = useRouter();
  const t = useTranslations("join");
  const { user, loading: authLoading } = useAuth();
  const [status, setStatus] = useState<"idle" | "accepting" | "success" | "error">("idle");
  const [personalName, setPersonalName] = useState<string>("");
  const [errorMsg, setErrorMsg] = useState<string>("");

  useEffect(() => {
    if (authLoading || !user || status !== "idle") return;

    setStatus("accepting");
    api.post<AcceptResult>(`/api/v1/invitations/${params.code}/accept`, {})
      .then((data) => {
        setPersonalName(data.personal_name);
        setStatus("success");
      })
      .catch(async (err) => {
        const body = await err.response?.json?.().catch(() => null);
        setErrorMsg(body?.error || t("error_generic"));
        setStatus("error");
      });
  }, [authLoading, user, params.code, status, t]);

  if (authLoading || status === "idle") {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50 dark:bg-gray-950">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary-500 border-t-transparent" />
      </div>
    );
  }

  if (!user) {
    const redirectUrl = `/join/${params.code}`;
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-5 bg-gray-50 px-6 dark:bg-gray-950">
        <div className="text-4xl">🤝</div>
        <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100 text-center">{t("title")}</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 text-center">
          Faça login ou crie sua conta para aceitar o convite.
        </p>
        <Link
          href={`/sign-up?redirect=${encodeURIComponent(redirectUrl)}`}
          className="w-full max-w-xs rounded-2xl bg-primary-500 py-3.5 text-center text-sm font-semibold text-white"
        >
          Criar conta grátis
        </Link>
        <Link
          href={`/login?redirect=${encodeURIComponent(redirectUrl)}`}
          className="text-sm text-primary-500 font-medium"
        >
          Já tenho conta — entrar
        </Link>
      </div>
    );
  }

  if (status === "accepting") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-gray-50 dark:bg-gray-950">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary-500 border-t-transparent" />
        <p className="text-sm text-gray-500 dark:text-gray-400">{t("accepting")}</p>
      </div>
    );
  }

  if (status === "success") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-5 bg-gray-50 px-6 dark:bg-gray-950">
        <div className="text-5xl">🎉</div>
        <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100">{t("success")}</h1>
        <p className="text-sm text-gray-600 dark:text-gray-400 text-center">
          {t("success_msg")} <strong>{personalName}</strong>.
        </p>
        <Link
          href="/dashboard"
          className="w-full max-w-xs rounded-2xl bg-primary-500 py-3.5 text-center text-sm font-semibold text-white"
        >
          {t("go_dashboard")}
        </Link>
        <Link href="/client/permissions" className="text-sm text-primary-500 font-medium">
          Configurar o que compartilho →
        </Link>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-5 bg-gray-50 px-6 dark:bg-gray-950">
      <div className="text-4xl">⚠️</div>
      <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100">Convite inválido</h1>
      <p className="text-sm text-gray-500 dark:text-gray-400 text-center">{errorMsg}</p>
      <Link href="/dashboard" className="text-sm text-primary-500 font-medium">← Ir para o painel</Link>
    </div>
  );
}
