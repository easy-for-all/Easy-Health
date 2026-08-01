"use client";

import Link from "next/link";
import { useEffect } from "react";
import { trackLoginSelected, trackSignupSelected } from "@/features/auth/auth-analytics";
import { trackOnce } from "@/shared/lib/analytics";

const SIGNUP_HREF = "/sign-up?intent=sign_up&from=native_entry";
const LOGIN_HREF = "/login?intent=login&from=native_entry";

export function NativeEntryScreen() {
  useEffect(() => {
    trackOnce("native_entry_viewed", "native_entry_viewed", {
      source: "native_app",
      platform: "android",
    });
  }, []);

  return (
    <main
      className="flex min-h-svh flex-col"
      style={{
        background: "#0a0f1e",
        color: "#f8fafc",
        paddingTop: "max(20px, var(--safe-area-top))",
        paddingRight: "max(18px, var(--safe-area-right))",
        paddingBottom: "max(18px, var(--safe-area-bottom))",
        paddingLeft: "max(18px, var(--safe-area-left))",
      }}
    >
      <div className="mx-auto flex min-h-[calc(100svh-var(--safe-area-top)-var(--safe-area-bottom)-38px)] w-full max-w-sm flex-col">
        <div className="flex items-center gap-3 pt-1">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="EasyHealth" className="h-10 w-10 rounded-xl" />
          <span
            className="text-xl font-extrabold tracking-normal text-white"
            style={{ fontFamily: "var(--font-display)" }}
          >
            EasyHealth
          </span>
        </div>

        <section className="flex flex-1 flex-col justify-center py-10">
          <div className="mb-9">
            <h1
              className="text-4xl font-extrabold leading-[1.04] tracking-normal text-white sm:text-5xl"
              style={{ fontFamily: "var(--font-display)" }}
            >
              Seu treino personalizado em menos de 1 minuto.
            </h1>
            <p className="mt-5 text-base leading-7 text-slate-300">
              A EasyHealth monta seu plano de acordo com seu objetivo, rotina e equipamentos.
            </p>
          </div>

          <div className="flex flex-col gap-3">
            <Link
              href={SIGNUP_HREF}
              onClick={() => trackSignupSelected("native_entry")}
              className="flex min-h-14 w-full items-center justify-center rounded-2xl bg-primary-500 px-5 py-4 text-center text-base font-extrabold text-white shadow-[var(--glow)]"
            >
              Criar meu treino grátis
            </Link>
            <Link
              href={LOGIN_HREF}
              onClick={() => trackLoginSelected("native_entry")}
              className="flex min-h-14 w-full items-center justify-center rounded-2xl border border-slate-700 bg-slate-900 px-5 py-4 text-center text-base font-bold text-white"
            >
              Já tenho uma conta
            </Link>
          </div>

          <p className="mt-5 text-center text-sm font-semibold text-slate-400">
            7 dias grátis · Sem cartão
          </p>
        </section>
      </div>
    </main>
  );
}
