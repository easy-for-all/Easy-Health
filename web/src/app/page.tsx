import Link from "next/link";
import type { Metadata } from "next";
import { Footer } from "@/shared/components/footer";
import { HeroCta } from "@/shared/components/hero-cta";
import { AnalyticsTracker } from "@/shared/components/analytics-tracker";
import { CONVERSIONS } from "@/shared/lib/analytics";

export const metadata: Metadata = {
  title: "EasyHealth — Treino inteligente com IA",
  description:
    "A EasyHealth monta seu plano, adapta a cada semana e te puxa pra treinar — do jeito que um personal faria, no seu bolso.",
};

// ── Phone mockup: dashboard replica ────────────────────────────────────────
function PhoneMockup() {
  return (
    <div className="relative grid place-items-center">
      {/* glow blob */}
      <div
        className="absolute -top-10 -right-8 w-72 h-72 rounded-full opacity-40 z-0"
        style={{ background: "#3b82f6", filter: "blur(70px)" }}
      />
      <div
        className="relative z-10 w-[310px] flex-none rounded-[46px] p-[13px] border border-slate-700"
        style={{
          background: "linear-gradient(160deg, #1e293b, #0f172a)",
          boxShadow: "0 18px 50px -18px rgba(0,0,0,.8), 0 50px 90px -50px rgba(0,0,0,.6)",
        }}
      >
        <div
          className="relative rounded-[34px] overflow-hidden flex flex-col"
          style={{ background: "#0a0f1e", aspectRatio: "310/620" }}
        >
          {/* notch */}
          <div className="absolute top-[10px] left-1/2 -translate-x-1/2 w-24 h-6 bg-black rounded-full z-10" />

          {/* appbar */}
          <div className="flex items-center justify-between px-[18px] pt-[38px] pb-2">
            <div className="leading-tight">
              <div className="text-[11px] text-slate-500">Olá,</div>
              <div className="text-[18px] font-extrabold text-white tracking-tight">MARCUS</div>
            </div>
            <div className="w-[30px] h-[30px] rounded-full border border-slate-700 grid place-items-center text-[13px] text-slate-400">
              ☾
            </div>
          </div>

          {/* scroll area */}
          <div className="flex-1 overflow-hidden px-[14px] pb-[14px] flex flex-col gap-[10px]">
            {/* train card */}
            <div
              className="rounded-[20px] p-[16px] relative overflow-hidden"
              style={{ background: "linear-gradient(150deg, #3b82f6, #2563eb)" }}
            >
              <div className="text-[10px] font-extrabold uppercase tracking-[.14em] text-blue-200 opacity-90">
                Domingo
              </div>
              <div className="text-[24px] font-extrabold text-white leading-tight my-1">Treinar agora</div>
              <div className="text-[11px] text-blue-100 mb-3">3 treinos no seu plano</div>
              <span className="inline-flex items-center gap-1.5 bg-white/15 text-white text-[12px] font-bold px-3 py-2 rounded-full">
                Escolher treino →
              </span>
            </div>

            {/* streak */}
            <div className="rounded-[15px] p-[13px] border border-slate-800 bg-slate-900">
              <div className="flex items-center justify-between mb-2.5">
                <span className="text-[12px] font-semibold text-white">🔥 Comece sua ofensiva</span>
                <span className="text-[15px] font-extrabold text-primary-400">0/3</span>
              </div>
              <div className="flex justify-between">
                {Array.from({ length: 7 }).map((_, i) => (
                  <span key={i} className="w-[10px] h-[10px] rounded-full bg-slate-800 border border-slate-700" />
                ))}
              </div>
            </div>

            <div className="text-[10px] font-extrabold uppercase tracking-[.14em] text-slate-500 mx-0.5">
              Seus treinos
            </div>

            {/* wkt A */}
            <div className="flex items-center gap-[11px] p-[11px] border border-slate-800 rounded-[14px] bg-slate-900">
              <span className="w-[29px] h-[29px] rounded-[9px] grid place-items-center text-[13px] font-extrabold text-primary-400 bg-primary-500/15">
                A
              </span>
              <div className="flex-1 min-w-0">
                <div className="text-[13px] font-semibold text-white">Full Body A</div>
                <div className="text-[10px] text-slate-500">6 exercícios · peito, costas</div>
              </div>
              <span className="text-[11px] font-bold text-slate-900 bg-primary-400 px-[11px] py-[6px] rounded-full">
                Treinar
              </span>
            </div>

            {/* wkt B */}
            <div className="flex items-center gap-[11px] p-[11px] border border-slate-800 rounded-[14px] bg-slate-900">
              <span className="w-[29px] h-[29px] rounded-[9px] grid place-items-center text-[13px] font-extrabold text-primary-400 bg-primary-500/15">
                B
              </span>
              <div className="flex-1 min-w-0">
                <div className="text-[13px] font-semibold text-white">Full Body B</div>
                <div className="text-[10px] text-slate-500">6 exercícios · ombros</div>
              </div>
              <span className="text-[11px] font-bold text-slate-900 bg-primary-400 px-[11px] py-[6px] rounded-full">
                Treinar
              </span>
            </div>
          </div>

          {/* tabbar */}
          <div className="flex justify-around px-2 py-[10px] border-t border-slate-800 bg-slate-900">
            {[
              {
                label: "Perfil",
                active: false,
                path: "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v1h16v-1c0-2.66-5.33-4-8-4z",
              },
              {
                label: "Treino",
                active: true,
                path: "M6 8v8M18 8v8M4 10h2M18 10h2M6 12h12",
              },
              {
                label: "Treinos",
                active: false,
                path: "M9 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-2M9 3a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2M9 3a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2",
              },
              {
                label: "Plano",
                active: false,
                path: "M3 6h18M3 10h18M3 14h18M3 18h18",
              },
            ].map((tab) => (
              <div
                key={tab.label}
                className={`flex flex-col items-center gap-1 text-[9px] font-semibold ${tab.active ? "text-primary-400" : "text-slate-600"}`}
              >
                <svg
                  className="w-[18px] h-[18px]"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d={tab.path} />
                </svg>
                {tab.label}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Mini phone: onboarding ──────────────────────────────────────────────────
function MiniPhoneOnboarding() {
  return (
    <MiniPhoneShell>
      <div className="p-[18px] flex flex-col gap-[10px] h-full">
        <div className="flex gap-[5px]">
          {[true, false, false, false, false].map((on, i) => (
            <div
              key={i}
              className={`h-[5px] flex-1 rounded-full ${on ? "bg-primary-500" : "bg-slate-800"}`}
            />
          ))}
        </div>
        <h4 className="text-[15px] font-bold text-white mt-2">Qual é o seu objetivo?</h4>
        {[
          { label: "Perder peso", sub: "Reduzir gordura corporal", sel: false },
          { label: "Ganhar músculo", sub: "Aumentar massa muscular", sel: true },
          { label: "Manter", sub: "Manter o peso atual", sel: false },
        ].map((opt) => (
          <div
            key={opt.label}
            className={`rounded-[11px] px-[12px] py-[10px] text-[12px] font-semibold border ${
              opt.sel
                ? "border-primary-500 bg-primary-500/12 text-primary-400"
                : "border-slate-700 bg-slate-900 text-white"
            }`}
          >
            {opt.label}
            <div className={`text-[10px] font-normal mt-0.5 ${opt.sel ? "text-primary-400/80" : "text-slate-500"}`}>
              {opt.sub}
            </div>
          </div>
        ))}
      </div>
    </MiniPhoneShell>
  );
}

// ── Mini phone: IA loading ──────────────────────────────────────────────────
function MiniPhoneLoading() {
  const lines = [
    { text: "Analisando seu perfil", done: true },
    { text: "Definindo divisão semanal", done: true },
    { text: "Selecionando exercícios", done: true },
    { text: "Ajustando intensidade…", done: false },
  ];
  return (
    <MiniPhoneShell>
      <div className="p-[22px] flex flex-col gap-[12px] h-full">
        {/* loading ring */}
        <div
          className="w-[44px] h-[44px] rounded-full border-4 border-slate-800 border-t-primary-500 animate-spin mx-auto mt-3"
        />
        <div className="flex flex-col gap-[9px] mt-1">
          {lines.map((l) => (
            <div
              key={l.text}
              className={`flex items-center gap-[7px] text-[11.5px] font-semibold ${
                l.done ? "text-primary-400" : "text-slate-600"
              }`}
            >
              {l.done ? (
                <svg className="w-[14px] h-[14px] flex-none" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                  <path d="M20 6L9 17l-5-5" />
                </svg>
              ) : (
                <div className="w-[14px] h-[14px] flex-none rounded-full border border-slate-700" />
              )}
              {l.text}
            </div>
          ))}
        </div>
      </div>
    </MiniPhoneShell>
  );
}

// ── Mini phone: treino ativo ────────────────────────────────────────────────
function MiniPhoneActive() {
  return (
    <MiniPhoneShell>
      <div className="flex flex-col h-full">
        <div
          className="grid place-items-center"
          style={{ aspectRatio: "16/10", background: "linear-gradient(135deg, #1e3a5f, #1e293b)" }}
        >
          <svg className="w-[38px] h-[38px] text-slate-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M6 8v8M18 8v8M4 10h2M18 10h2M6 12h12" />
          </svg>
        </div>
        <div className="p-[13px] flex flex-col gap-[10px] flex-1">
          <h4 className="text-[16px] font-extrabold text-white">Bench Press</h4>
          <div className="flex gap-[7px]">
            {[
              { val: "4", label: "SÉRIES" },
              { val: "10", label: "REPS" },
              { val: "1", label: "ATUAL" },
            ].map((c) => (
              <div key={c.label} className="flex-1 bg-slate-800 rounded-[10px] p-[8px] text-center">
                <div className="text-[17px] font-extrabold text-white">{c.val}</div>
                <div className="text-[9px] text-slate-500">{c.label}</div>
              </div>
            ))}
          </div>
          <div
            className="mt-auto text-center font-extrabold text-[12px] py-[12px] rounded-[12px] text-white"
            style={{ background: "#3b82f6", boxShadow: "0 4px 16px rgba(59,130,246,.45)" }}
          >
            Feito — série 1/4
          </div>
        </div>
      </div>
    </MiniPhoneShell>
  );
}

function MiniPhoneShell({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="mx-auto w-[224px] rounded-[28px] p-[9px] border border-slate-700 mb-6"
      style={{
        background: "linear-gradient(160deg, #1e293b, #0f172a)",
        boxShadow: "0 18px 40px -20px rgba(0,0,0,.7)",
      }}
    >
      <div
        className="rounded-[21px] overflow-hidden flex flex-col"
        style={{ background: "#0a0f1e", aspectRatio: "224/372" }}
      >
        {children}
      </div>
    </div>
  );
}

// ── Feature icon wrappers ───────────────────────────────────────────────────
const FEATURES = [
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M12 3l1.9 5.8H20l-4.9 3.6 1.9 5.8L12 14.6 7 18.2l1.9-5.8L4 8.8h6.1z" />
      </svg>
    ),
    title: "Treino com IA",
    desc: "Responda algumas perguntas e a IA monta um plano sob medida pro seu objetivo, nível e rotina.",
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M6.5 6.5l11 11M17.5 6.5l-11 11" /><circle cx="4" cy="12" r="2" /><circle cx="20" cy="12" r="2" />
      </svg>
    ),
    title: "Personalizado de verdade",
    desc: "Cada exercício considera seu equipamento, local de treino e o que você gosta de fazer.",
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M12 2c1 5 6 6 6 11a6 6 0 0 1-12 0c0-2 1-3 2-4 .5 2 2 2 2 0 0-3 1-5 2-7z" />
      </svg>
    ),
    title: "Engajamento que pega",
    desc: "Ofensivas, sequências e metas semanais pra você não largar no terceiro dia.",
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M3 11l9-8 9 8" /><path d="M5 10v10h14V10" /><path d="M9 20v-6h6v6" />
      </svg>
    ),
    title: "Treino em casa ou rua",
    desc: "Academia, peso corporal, ar livre — o plano se adapta a onde você está hoje.",
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6M9 13h6M9 17h6" />
      </svg>
    ),
    title: "Análise de exames",
    desc: "Suba fotos e exames e receba estimativas de IMC, peso ideal, TMB e mais — só pra acompanhar.",
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-6 h-6 stroke-primary-400 fill-none stroke-[1.9] [stroke-linecap:round] [stroke-linejoin:round]">
        <path d="M12 1v22M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
      </svg>
    ),
    title: "Preço que cabe",
    desc: "A partir de R$9,90/mês no plano anual. Comece com 7 dias grátis, sem compromisso.",
  },
];

const STEPS = [
  {
    num: "PASSO 01",
    title: "Conte seu objetivo",
    desc: "Objetivo, nível, dados físicos e o que você curte. Leva menos de um minuto.",
    phone: <MiniPhoneOnboarding />,
  },
  {
    num: "PASSO 02",
    title: "A IA monta seu plano",
    desc: "Em segundos, a EasyHealth gera uma divisão semanal completa com os exercícios certos.",
    phone: <MiniPhoneLoading />,
  },
  {
    num: "PASSO 03",
    title: "Treine e registre",
    desc: "Acompanhe séries, reps, descanso e carga. No fim, veja seu resumo e ofensiva.",
    phone: <MiniPhoneActive />,
  },
];

// ── Page ────────────────────────────────────────────────────────────────────
export default function LandingPage() {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "#0a0f1e", color: "#f0f4ff" }}>
      <AnalyticsTracker eventName="landing_view" conversionLabel={CONVERSIONS.PAGE_VIEW} />
      <AnalyticsTracker eventName="screen_view" params={{ screen_name: "home" }} />

      {/* ── NAV ── */}
      <header
        className="sticky top-0 z-50 border-b border-slate-800/70 backdrop-blur-xl"
        style={{ background: "rgba(10,15,30,0.82)" }}
      >
        <div className="mx-auto flex max-w-[1180px] items-center justify-between h-[72px] px-6">
          <Link href="/" className="flex items-center gap-[10px] font-extrabold text-[21px] tracking-tight text-white no-underline">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.png" alt="EasyHealth" className="h-8 w-auto" />
            EasyHealth
          </Link>
          <nav className="flex items-center gap-3">
            <a href="#funciona" className="hidden sm:block text-[15px] font-semibold text-slate-400 hover:text-white transition-colors px-3 py-2 no-underline">
              Como funciona
            </a>
            <a href="#planos" className="hidden sm:block text-[15px] font-semibold text-slate-400 hover:text-white transition-colors px-3 py-2 no-underline">
              Planos
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

      <main className="flex-1">
        {/* ── HERO ── */}
        <section
          className="relative overflow-hidden"
          style={{
            background:
              "radial-gradient(110% 100% at 100% 0%, rgba(30,58,95,0.7) 0%, transparent 55%), #0a0f1e",
          }}
        >
          <div className="mx-auto max-w-[1180px] px-6 grid gap-[clamp(30px,5vw,70px)] items-center py-[clamp(48px,7vw,96px)] sm:grid-cols-[1.05fr_0.95fr] grid-cols-1">
            {/* copy */}
            <div className="max-sm:text-center">
              {/* pill */}
              <div className="inline-flex items-center gap-[9px] mb-[26px] px-[14px] py-[8px] rounded-full border border-slate-700 bg-slate-900 text-[13px] font-semibold text-slate-400">
                <span className="w-2 h-2 rounded-full bg-primary-500" style={{ boxShadow: "0 0 0 4px rgba(59,130,246,.25)" }} />
                <b className="text-white font-bold">+300 treinos gerados</b> · Grátis por 7 dias
              </div>

              <h1
                className="text-[clamp(40px,6.4vw,78px)] font-extrabold leading-[1.02] tracking-tight mb-5"
                style={{ textWrap: "balance" } as React.CSSProperties}
              >
                Treino com IA pra você evoluir com{" "}
                <span className="text-primary-400">constância</span>.
              </h1>

              <p className="text-[clamp(17px,1.4vw,21px)] text-slate-400 max-w-[30ch] mb-8 leading-[1.5] max-sm:mx-auto">
                A EasyHealth monta seu plano, adapta a cada semana e te puxa pra treinar — do jeito que um personal faria, no seu bolso.
              </p>

              <div className="flex gap-[14px] flex-wrap max-sm:justify-center">
                <HeroCta />
                <a
                  href="#funciona"
                  className="inline-flex items-center rounded-full border border-slate-600 hover:border-slate-400 text-white text-[17px] font-bold px-[34px] py-[19px] transition-all hover:-translate-y-0.5 no-underline"
                >
                  Ver como funciona
                </a>
              </div>

              <div className="mt-[18px] text-[13.5px] text-slate-500 flex items-center gap-2 max-sm:justify-center">
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M20 6L9 17l-5-5" />
                </svg>
                Sem cartão de crédito · Cancele quando quiser
              </div>
            </div>

            {/* phone */}
            <div className="max-sm:order-first max-sm:mb-3 max-sm:flex max-sm:justify-center">
              <PhoneMockup />
            </div>
          </div>
        </section>

        {/* ── STATS ── */}
        <section className="border-t border-b border-slate-800" style={{ background: "#111827" }}>
          <div className="mx-auto max-w-[1180px] px-6 grid grid-cols-2 sm:grid-cols-4 gap-6 py-[34px]">
            {[
              { val: "+300", label: "treinos gerados" },
              { val: "IA", label: "adapta toda semana" },
              { val: "7 dias", label: "grátis pra testar" },
              { val: "R$9,90", label: "por mês no plano anual" },
            ].map((s) => (
              <div key={s.label} className="text-center">
                <div className="text-[clamp(28px,3.4vw,42px)] font-extrabold tracking-tight text-white">{s.val}</div>
                <div className="text-[13px] text-slate-400 font-semibold mt-0.5">{s.label}</div>
              </div>
            ))}
          </div>
        </section>

        {/* ── FEATURES ── */}
        <section className="py-[clamp(64px,9vw,120px)]" id="recursos">
          <div className="mx-auto max-w-[1180px] px-6">
            <div className="mb-[52px]">
              <div className="text-[12.5px] font-extrabold uppercase tracking-[.16em] text-primary-400 mb-3">
                O que a EasyHealth faz por você
              </div>
              <h2
                className="text-[clamp(31px,4.6vw,54px)] font-extrabold tracking-tight leading-[1.02]"
                style={{ textWrap: "balance" } as React.CSSProperties}
              >
                Um personal trainer que cabe no seu dia.
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-[18px]">
              {FEATURES.map((f) => (
                <div
                  key={f.title}
                  className="rounded-[22px] border border-slate-800 p-[26px] bg-slate-900/60 transition-all duration-200 hover:-translate-y-1 hover:border-slate-600 cursor-default"
                >
                  <div className="w-12 h-12 rounded-[13px] grid place-items-center mb-[18px] bg-primary-500/15">
                    {f.icon}
                  </div>
                  <h3 className="text-[20px] font-bold tracking-tight mb-2 text-white">{f.title}</h3>
                  <p className="text-slate-400 text-[15px] leading-[1.5] m-0">{f.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── COMO FUNCIONA ── */}
        <section className="py-[clamp(64px,9vw,120px)]" id="funciona" style={{ background: "#111827" }}>
          <div className="mx-auto max-w-[1180px] px-6">
            <div className="text-center mb-[52px]">
              <div className="text-[12.5px] font-extrabold uppercase tracking-[.16em] text-primary-400 mb-3">
                Como funciona na prática
              </div>
              <h2
                className="text-[clamp(31px,4.6vw,54px)] font-extrabold tracking-tight leading-[1.02]"
                style={{ textWrap: "balance" } as React.CSSProperties}
              >
                Três passos até o primeiro treino.
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-[26px]">
              {STEPS.map((s) => (
                <div key={s.num} className="text-center">
                  {s.phone}
                  <div className="text-[12px] font-extrabold tracking-[.12em] text-primary-400 mb-2">{s.num}</div>
                  <h3 className="text-[22px] font-bold tracking-tight mb-2 text-white">{s.title}</h3>
                  <p className="text-slate-400 text-[14.5px] leading-[1.5] max-w-[28ch] mx-auto m-0">{s.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── PRICING ── */}
        <section className="py-[clamp(64px,9vw,120px)]" id="planos" style={{ background: "#111827" }}>
          <div className="mx-auto max-w-[1180px] px-6">
            <div className="text-center mb-[52px]">
              <div className="text-[12.5px] font-extrabold uppercase tracking-[.16em] text-primary-400 mb-3">Planos</div>
              <h2
                className="text-[clamp(31px,4.6vw,54px)] font-extrabold tracking-tight leading-[1.02]"
                style={{ textWrap: "balance" } as React.CSSProperties}
              >
                Comece grátis. Continue se valer a pena.
              </h2>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5 max-w-[760px] mx-auto">
              {/* Mensal */}
              <div className="rounded-[22px] border border-slate-700 p-[30px] bg-slate-900/60">
                <h3 className="text-[19px] font-bold text-white mb-1.5">Pro Mensal</h3>
                <div className="text-[44px] font-extrabold tracking-tight text-white leading-none">
                  R$ 19,90<span className="text-[16px] text-slate-400 font-semibold">/mês</span>
                </div>
                <div className="text-[13.5px] text-slate-500 mt-1 mb-5">Depois de 7 dias grátis</div>
                <ul className="list-none p-0 m-0 flex flex-col gap-[11px] mb-6">
                  {["Acesso completo a todos os recursos", "Treinos personalizados por IA", "Histórico ilimitado"].map(
                    (item) => (
                      <li key={item} className="flex gap-[10px] text-[15px] text-slate-400 items-start">
                        <svg className="w-[18px] h-[18px] flex-none mt-0.5 stroke-primary-400 fill-none" strokeWidth="2.4" viewBox="0 0 24 24">
                          <path d="M20 6L9 17l-5-5" />
                        </svg>
                        {item}
                      </li>
                    )
                  )}
                </ul>
                <Link
                  href="/sign-up"
                  className="w-full flex justify-center items-center rounded-full border border-slate-600 hover:border-slate-400 text-white text-[16px] font-bold px-6 py-4 transition-all hover:-translate-y-0.5 no-underline"
                >
                  Começar 7 dias grátis
                </Link>
              </div>

              {/* Anual */}
              <div
                className="rounded-[22px] border p-[30px] relative bg-slate-900/60"
                style={{
                  borderColor: "#3b82f6",
                  boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 8px 40px rgba(59,130,246,.18)",
                }}
              >
                <span
                  className="absolute -top-[13px] left-1/2 -translate-x-1/2 bg-primary-500 text-white text-[12px] font-extrabold px-4 py-[6px] rounded-full"
                >
                  Mais vantajoso
                </span>
                <h3 className="text-[19px] font-bold text-white mb-1.5">Pro Anual</h3>
                <div className="text-[44px] font-extrabold tracking-tight text-white leading-none">
                  R$ 9,90<span className="text-[16px] text-slate-400 font-semibold">/mês</span>
                </div>
                <div className="text-[14px] text-primary-400 font-bold mt-1 mb-5">R$ 118,80/ano · economize ~50%</div>
                <ul className="list-none p-0 m-0 flex flex-col gap-[11px] mb-6">
                  {["Tudo do Pro Mensal", "Metade do preço por mês", "7 dias grátis pra testar"].map((item) => (
                    <li key={item} className="flex gap-[10px] text-[15px] text-slate-400 items-start">
                      <svg className="w-[18px] h-[18px] flex-none mt-0.5 stroke-primary-400 fill-none" strokeWidth="2.4" viewBox="0 0 24 24">
                        <path d="M20 6L9 17l-5-5" />
                      </svg>
                      {item}
                    </li>
                  ))}
                </ul>
                <Link
                  href="/sign-up"
                  className="w-full flex justify-center items-center rounded-full bg-primary-500 hover:bg-primary-600 text-white text-[16px] font-bold px-6 py-4 transition-all hover:-translate-y-0.5 no-underline"
                  style={{ boxShadow: "0 0 0 1px rgba(59,130,246,.35), 0 8px 24px rgba(59,130,246,.3)" }}
                >
                  Começar 7 dias grátis
                </Link>
              </div>
            </div>
          </div>
        </section>

        {/* ── FINAL CTA ── */}
        <section className="py-[clamp(64px,9vw,120px)] text-center">
          <div className="mx-auto max-w-[1180px] px-6">
            <div
              className="rounded-[30px] px-[30px] py-[clamp(46px,7vw,88px)] relative overflow-hidden"
              style={{ background: "linear-gradient(150deg, #2563eb, #1d4ed8)" }}
            >
              <h2
                className="text-[clamp(30px,4.6vw,56px)] font-extrabold tracking-tight leading-[1.02] text-white mb-4"
                style={{ textWrap: "balance" } as React.CSSProperties}
              >
                Comece hoje com 7 dias grátis.
              </h2>
              <p className="text-[18px] text-blue-100 opacity-90 mb-8">
                Sem cartão de crédito pra começar. Cancele quando quiser.
              </p>
              <Link
                href="/sign-up"
                className="inline-flex items-center rounded-full bg-white text-primary-700 text-[17.5px] font-bold px-[34px] py-[19px] hover:bg-blue-50 transition-all hover:-translate-y-0.5 no-underline"
              >
                Criar conta grátis →
              </Link>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
