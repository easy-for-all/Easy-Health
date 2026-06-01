import Link from "next/link";
import { Footer } from "./footer";
import { SupportChat } from "./support-chat";

export function PublicLayout({ children }: { children: React.ReactNode }) {
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
              className="rounded-full bg-primary-500 hover:bg-primary-600 text-white text-[15px] font-bold px-5 py-[10px] transition-all hover:-translate-y-0.5 no-underline"
              style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 8px 24px rgba(59,130,246,.3)" }}
            >
              Criar conta
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">{children}</main>

      <Footer />
      <SupportChat />
    </div>
  );
}
