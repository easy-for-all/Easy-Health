"use client";

import { useState } from "react";
import Link from "next/link";
import { Footer } from "./footer";
import { SupportChat } from "./support-chat";

export function PublicLayout({ children }: { children: React.ReactNode }) {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "#0a0f1e" }}>
      <header className="sticky top-0 z-50 border-b border-slate-800/70 backdrop-blur-xl" style={{ background: "rgba(10,15,30,0.82)" }}>
        <div className="mx-auto flex max-w-[1180px] items-center justify-between h-[72px] px-6">
          <Link href="/" className="flex items-center gap-[10px] font-extrabold text-[21px] tracking-tight text-white no-underline">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.png" alt="EasyHealth" className="h-8 w-auto" />
            EasyHealth
          </Link>
          <nav className="flex items-center gap-3">
            <Link href="/precos" className="hidden sm:block text-[15px] font-semibold text-slate-400 hover:text-white transition-colors px-3 py-2 no-underline">
              Preços
            </Link>
            <a href="mailto:suporte@easyhealth.com.br" className="hidden sm:block text-[15px] font-semibold text-slate-400 hover:text-white transition-colors px-3 py-2 no-underline">
              Fale Conosco
            </a>
            <Link href="/login" className="hidden sm:block text-[15px] font-semibold text-slate-400 hover:text-white transition-colors px-3 py-2 no-underline">
              Entrar
            </Link>
            <Link
              href="/sign-up"
              className="hidden sm:block rounded-full bg-primary-500 hover:bg-primary-600 text-white text-[15px] font-bold px-5 py-[10px] transition-all hover:-translate-y-0.5 no-underline"
              style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 8px 24px rgba(59,130,246,.3)" }}
            >
              Criar conta
            </Link>

            {/* Mobile: CTA + hamburger */}
            <Link
              href="/sign-up"
              className="sm:hidden rounded-full bg-primary-500 hover:bg-primary-600 text-white text-[14px] font-bold px-4 py-2 transition-all no-underline"
              style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 6px 16px rgba(59,130,246,.28)" }}
            >
              Criar conta
            </Link>
            <button
              className="sm:hidden p-2 text-slate-400 hover:text-white transition-colors"
              onClick={() => setMenuOpen((v) => !v)}
              aria-label={menuOpen ? "Fechar menu" : "Abrir menu"}
            >
              {menuOpen ? (
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              ) : (
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                  <line x1="3" y1="6" x2="21" y2="6" />
                  <line x1="3" y1="12" x2="21" y2="12" />
                  <line x1="3" y1="18" x2="21" y2="18" />
                </svg>
              )}
            </button>
          </nav>
        </div>

        {/* Mobile dropdown menu */}
        {menuOpen && (
          <div className="sm:hidden border-t border-slate-800/70 px-6 py-4 flex flex-col gap-1" style={{ background: "rgba(10,15,30,0.97)" }}>
            <Link
              href="/precos"
              onClick={() => setMenuOpen(false)}
              className="block rounded-xl px-4 py-3 text-[15px] font-semibold text-slate-300 hover:bg-slate-800 hover:text-white transition-colors no-underline"
            >
              Preços
            </Link>
            <Link
              href="/login"
              onClick={() => setMenuOpen(false)}
              className="block rounded-xl px-4 py-3 text-[15px] font-semibold text-slate-300 hover:bg-slate-800 hover:text-white transition-colors no-underline"
            >
              Entrar
            </Link>
            <a
              href="mailto:suporte@easyhealth.com.br"
              onClick={() => setMenuOpen(false)}
              className="block rounded-xl px-4 py-3 text-[15px] font-semibold text-slate-300 hover:bg-slate-800 hover:text-white transition-colors no-underline"
            >
              Fale Conosco
            </a>
          </div>
        )}
      </header>

      <main className="flex-1">{children}</main>

      <Footer />
      <SupportChat />
    </div>
  );
}
