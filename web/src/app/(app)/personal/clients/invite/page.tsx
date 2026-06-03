"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCreateInvitation } from "@/features/personal/use-personal";

export default function PersonalInvitePage() {
  const t = useTranslations("personal");
  const router = useRouter();
  const { create, loading, result } = useCreateInvitation();

  return (
    <div className="min-h-screen bg-gray-50 pb-24 dark:bg-gray-950">
      <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-100 bg-white/90 px-4 py-4 backdrop-blur-sm dark:border-gray-800 dark:bg-gray-950/90">
        <button onClick={() => router.back()} className="text-gray-500 dark:text-gray-400">←</button>
        <h1 className="text-base font-semibold text-gray-900 dark:text-gray-100">{t("invite_title")}</h1>
      </header>

      <div className="mx-auto max-w-lg px-4 py-6 space-y-5">
        <p className="text-sm text-gray-600 dark:text-gray-400">{t("invite_subtitle")}</p>

        {!result ? (
          <button
            onClick={create}
            disabled={loading}
            className="w-full rounded-2xl bg-primary-500 py-4 text-sm font-semibold text-white disabled:opacity-50"
          >
            {loading ? t("generating") : t("generate_invite")}
          </button>
        ) : (
          <div className="space-y-4">
            <div className="rounded-2xl bg-white p-5 shadow-sm dark:bg-gray-900">
              <p className="mb-2 text-xs text-gray-500 dark:text-gray-400">{t("invite_title")}</p>
              <p className="break-all rounded-lg bg-gray-50 px-3 py-3 text-sm font-mono text-gray-900 dark:bg-gray-800 dark:text-gray-100">
                {result.invite_url}
              </p>
              <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">
                {t("expires_in")}: {new Date(result.expires_at).toLocaleString()}
              </p>
            </div>

            <CopyButton url={result.invite_url} label={t("copy_link")} copied={t("copied")} />

            <ShareButtons url={result.invite_url} />

            <button
              onClick={create}
              disabled={loading}
              className="w-full rounded-2xl border border-gray-200 py-3 text-sm font-medium text-gray-700 dark:border-gray-700 dark:text-gray-300"
            >
              Gerar novo link
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function CopyButton({ url, label, copied }: { url: string; label: string; copied: string }) {
  const [isCopied, setIsCopied] = useState(false);

  function copy() {
    navigator.clipboard.writeText(url);
    setIsCopied(true);
    setTimeout(() => setIsCopied(false), 2000);
  }

  return (
    <button
      onClick={copy}
      className="w-full rounded-2xl bg-primary-500 py-3.5 text-sm font-semibold text-white transition-colors hover:bg-primary-600"
    >
      {isCopied ? copied : label}
    </button>
  );
}

function ShareButtons({ url }: { url: string }) {
  if (typeof navigator === "undefined" || !navigator.share) return null;

  return (
    <button
      onClick={() => navigator.share({ title: "Convite EasyHealth", url })}
      className="w-full rounded-2xl border border-gray-200 py-3.5 text-sm font-semibold text-gray-700 dark:border-gray-700 dark:text-gray-300"
    >
      Compartilhar via...
    </button>
  );
}

// useState import needed
import { useState } from "react";
