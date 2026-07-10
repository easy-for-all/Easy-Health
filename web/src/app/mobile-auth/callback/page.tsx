"use client";

import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import {
  buildCustomSchemeCallbackUrl,
  parseMobileAuthCallback,
  removeSensitiveMobileAuthParams,
  type ParsedMobileAuthCallback,
} from "@/shared/lib/mobileAuth";

type CallbackState = "opening" | "needs-tap" | "error";

export default function MobileAuthCallbackPage() {
  const searchParams = useSearchParams();
  const [state, setState] = useState<CallbackState>("opening");
  const [parsed, setParsed] = useState<ParsedMobileAuthCallback | null>(null);

  const callbackUrl = useMemo(() => {
    const query = searchParams.toString();
    return `https://easyhealth.art/mobile-auth/callback${query ? `?${query}` : ""}`;
  }, [searchParams]);

  useEffect(() => {
    const result = parseMobileAuthCallback(callbackUrl);
    removeSensitiveMobileAuthParams();

    if (!result || result.type === "legacy-token") {
      const timeout = window.setTimeout(() => setState("error"), 0);
      return () => window.clearTimeout(timeout);
    }

    setParsed(result);

    // Attempt the automatic redirect (carries the code, or the error for the app
    // to handle). Permissive browsers (e.g. the emulator's) launch the app right
    // away. Chrome on physical devices blocks a custom scheme navigation that
    // isn't triggered by a user gesture, so after a short grace period we surface
    // a button the user can tap (a real user gesture, which Chrome allows)
    // instead of failing silently.
    window.location.href = buildCustomSchemeCallbackUrl(result);

    const timeout = window.setTimeout(() => {
      setState((prev) => (prev === "opening" ? "needs-tap" : prev));
    }, 1500);

    return () => window.clearTimeout(timeout);
  }, [callbackUrl]);

  function openApp() {
    if (!parsed) return;
    window.location.href = buildCustomSchemeCallbackUrl(parsed);
  }

  const title =
    state === "opening"
      ? "Login concluído, abrindo seu app..."
      : state === "needs-tap"
        ? "Quase lá! Toque para voltar ao app"
        : "Não conseguimos concluir o login.";

  const subtitle =
    state === "opening"
      ? "Aguarde um instante enquanto voltamos para o EasyHealth."
      : state === "needs-tap"
        ? "Toque no botão abaixo para abrir o EasyHealth e concluir o login."
        : "Volte ao app e tente entrar com Google novamente.";

  return (
    <main className="flex min-h-svh items-center justify-center bg-[#0a0f1e] px-6 text-center text-white">
      <div className="w-full max-w-sm">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="EasyHealth" className="mx-auto h-14 w-14 rounded-2xl" />
        <h1 className="mt-6 text-xl font-bold">{title}</h1>
        <p className="mt-3 text-sm leading-6 text-slate-400">{subtitle}</p>

        {state === "needs-tap" && parsed && (
          <button
            type="button"
            onClick={openApp}
            className="mt-6 w-full rounded-2xl bg-gradient-to-b from-indigo-500 to-indigo-600 px-6 py-4 text-base font-bold text-white shadow-lg transition active:scale-[0.98]"
          >
            Abrir o EasyHealth
          </button>
        )}
      </div>
    </main>
  );
}
