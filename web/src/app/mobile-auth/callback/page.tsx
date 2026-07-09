"use client";

import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import {
  buildCustomSchemeCallbackUrl,
  parseMobileAuthCallback,
  removeSensitiveMobileAuthParams,
} from "@/shared/lib/mobileAuth";

type CallbackState = "opening" | "error";

export default function MobileAuthCallbackPage() {
  const searchParams = useSearchParams();
  const [state, setState] = useState<CallbackState>("opening");

  const callbackUrl = useMemo(() => {
    const query = searchParams.toString();
    return `https://easyhealth.art/mobile-auth/callback${query ? `?${query}` : ""}`;
  }, [searchParams]);

  useEffect(() => {
    const parsed = parseMobileAuthCallback(callbackUrl);
    removeSensitiveMobileAuthParams();

    if (!parsed || parsed.type === "legacy-token") {
      const timeout = window.setTimeout(() => setState("error"), 0);
      return () => window.clearTimeout(timeout);
    }

    window.location.href = buildCustomSchemeCallbackUrl(parsed);

    const timeout = window.setTimeout(() => {
      setState("error");
    }, 2500);

    return () => window.clearTimeout(timeout);
  }, [callbackUrl]);

  return (
    <main className="flex min-h-svh items-center justify-center bg-[#0a0f1e] px-6 text-center text-white">
      <div className="w-full max-w-sm">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="EasyHealth" className="mx-auto h-14 w-14 rounded-2xl" />
        <h1 className="mt-6 text-xl font-bold">
          {state === "opening" ? "Login concluído, abrindo seu app..." : "Não conseguimos concluir o login."}
        </h1>
        <p className="mt-3 text-sm leading-6 text-slate-400">
          {state === "opening"
            ? "Aguarde um instante enquanto voltamos para o EasyHealth."
            : "Volte ao app e tente entrar com Google novamente."}
        </p>
      </div>
    </main>
  );
}
