import Link from "next/link";
import type { Metadata } from "next";
import { Footer } from "@/shared/components/footer";
import { HeroCta } from "@/shared/components/hero-cta";
import { AnalyticsTracker } from "@/shared/components/analytics-tracker";
import { LandingHeader } from "@/shared/components/landing-header";
import { CONVERSIONS } from "@/shared/lib/analytics";
import { AppPromoCard } from "@/features/app-promo/app-promo-card";

export const metadata: Metadata = {
  title: "EasyHealth — Treino inteligente com IA",
  description:
    "A EasyHealth monta seu plano, adapta a cada semana e te puxa pra treinar — do jeito que um personal faria, no seu bolso.",
};

// ── Phone mockup ──────────────────────────────────────────────────────────────

function PhoneMockup() {
  return (
    <div style={{ position: "relative", display: "grid", placeItems: "center" }}>
      {/* glow blob */}
      <div style={{ position: "absolute", top: -40, right: -30, width: 280, height: 280, borderRadius: "50%", background: "var(--primary)", filter: "blur(70px)", opacity: .45, zIndex: 0 }} />
      <div
        style={{
          position: "relative", zIndex: 2, width: 310, flexShrink: 0,
          borderRadius: 46, padding: 13,
          background: "linear-gradient(160deg, var(--surface-2), var(--surface))",
          border: "1px solid var(--border-strong)",
          boxShadow: "var(--shadow-lg), 0 50px 90px -50px rgba(0,0,0,.6)",
        }}
      >
        <div style={{ borderRadius: 34, overflow: "hidden", background: "var(--bg)", aspectRatio: "310/620", display: "flex", flexDirection: "column" }}>
          {/* notch */}
          <div style={{ position: "absolute", top: 10, left: "50%", transform: "translateX(-50%)", width: 96, height: 24, background: "#06070a", borderRadius: 999, zIndex: 6 }} />

          {/* appbar */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "38px 18px 8px" }}>
            <div style={{ lineHeight: 1.2 }}>
              <div style={{ fontSize: 11, color: "var(--text-dim)" }}>Olá,</div>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 19, fontWeight: 800, letterSpacing: "-0.01em", color: "var(--text)" }}>MARCUS</div>
            </div>
            <div style={{ width: 30, height: 30, borderRadius: "50%", border: "1px solid var(--border)", display: "grid", placeItems: "center", fontSize: 13, color: "var(--text-dim)" }}>☾</div>
          </div>

          <div style={{ flex: 1, overflow: "hidden", padding: "6px 14px 14px", display: "flex", flexDirection: "column", gap: 11 }}>
            {/* hero card */}
            <div style={{ borderRadius: 20, padding: 17, color: "var(--on-primary)", background: "linear-gradient(150deg, var(--primary), var(--primary-2))", position: "relative", overflow: "hidden" }}>
              <div style={{ fontSize: 10, fontWeight: 800, letterSpacing: ".14em", textTransform: "uppercase", opacity: .85 }}>Domingo</div>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 25, fontWeight: 800, margin: "4px 0 3px", letterSpacing: "-0.01em" }}>Treinar agora</div>
              <div style={{ fontSize: 12, opacity: .82, marginBottom: 13 }}>3 treinos no seu plano</div>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 6, background: "var(--surface)", color: "var(--text)", fontWeight: 700, fontSize: 12.5, padding: "9px 14px", borderRadius: 999 }}>
                Escolher treino →
              </span>
            </div>

            {/* streak */}
            <div style={{ border: "1px solid var(--border)", borderRadius: 16, padding: 13, background: "var(--surface)" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>🔥 Comece sua ofensiva</span>
                <span style={{ fontFamily: "var(--font-display)", fontWeight: 800, color: "var(--primary)", fontSize: 16 }}>0/3</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", marginTop: 11 }}>
                {Array.from({ length: 7 }).map((_, i) => (
                  <span key={i} style={{ width: 11, height: 11, borderRadius: "50%", background: "var(--bg-2)", border: "1px solid var(--border)" }} />
                ))}
              </div>
            </div>

            <div style={{ fontSize: 10, fontWeight: 800, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--text-dim)", margin: "2px 2px -2px" }}>Seus treinos</div>

            {/* workout rows */}
            {[{ l: "A", name: "Full Body A", sub: "6 ex · peito, costas" }, { l: "B", name: "Full Body B", sub: "6 ex · ombros, core" }].map((w) => (
              <div key={w.l} style={{ display: "flex", alignItems: "center", gap: 11, padding: 12, border: "1px solid var(--border)", borderRadius: 15, background: "var(--surface)" }}>
                <span style={{ width: 30, height: 30, borderRadius: 9, display: "grid", placeItems: "center", fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 14, background: "var(--primary-soft)", color: "var(--primary)" }}>{w.l}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13.5, fontWeight: 700 }}>{w.name}</div>
                  <div style={{ fontSize: 11, color: "var(--text-dim)" }}>{w.sub}</div>
                </div>
                <span style={{ fontSize: 11, fontWeight: 800, color: "var(--on-primary)", background: "var(--primary)", padding: "7px 12px", borderRadius: 999 }}>Treinar</span>
              </div>
            ))}
          </div>

          {/* tab bar */}
          <div style={{ display: "flex", justifyContent: "space-around", padding: "10px 8px 14px", borderTop: "1px solid var(--border)", background: "var(--surface)" }}>
            {[{ label: "Perfil", on: false }, { label: "Hoje", on: true }, { label: "Treinos", on: false }, { label: "Plano", on: false }].map((tab) => (
              <div key={tab.label} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 3, fontSize: 9.5, fontWeight: 600, color: tab.on ? "var(--primary)" : "var(--text-dim)" }}>
                <div style={{ width: 18, height: 18, borderRadius: "50%", background: tab.on ? "var(--primary-soft)" : "transparent", border: tab.on ? "1px solid var(--primary)" : "none" }} />
                {tab.label}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Mini phone shell ──────────────────────────────────────────────────────────

function MiniShell({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ margin: "0 auto 24px", width: 224, borderRadius: 28, padding: 9, background: "linear-gradient(160deg, var(--surface-2), var(--surface))", border: "1px solid var(--border-strong)", boxShadow: "var(--shadow)" }}>
      <div style={{ borderRadius: 21, overflow: "hidden", background: "var(--bg)", aspectRatio: "224/372", display: "flex", flexDirection: "column" }}>
        {children}
      </div>
    </div>
  );
}

function MiniOnboarding() {
  return (
    <MiniShell>
      <div style={{ padding: "18px 15px", display: "flex", flexDirection: "column", gap: 10, height: "100%" }}>
        <div style={{ display: "flex", gap: 5 }}>
          {[true, false, false, false, false].map((on, i) => (
            <div key={i} style={{ height: 5, flex: 1, borderRadius: 9, background: on ? "var(--primary)" : "var(--bg-2)" }} />
          ))}
        </div>
        <h4 style={{ fontFamily: "var(--font-display)", fontSize: 15, fontWeight: 700, margin: "8px 0 0" }}>Qual é o seu objetivo?</h4>
        {[
          { label: "Perder peso",    sub: "Reduzir gordura corporal",   sel: false },
          { label: "Ganhar músculo", sub: "Aumentar massa muscular",    sel: true  },
          { label: "Manter",         sub: "Manter o peso atual",        sel: false },
        ].map((opt) => (
          <div key={opt.label} style={{ border: `1px solid ${opt.sel ? "var(--primary)" : "var(--border)"}`, borderRadius: 12, padding: "11px 13px", fontSize: 12.5, fontWeight: 600, background: opt.sel ? "var(--primary-soft)" : "var(--surface)", color: opt.sel ? "var(--primary)" : "var(--text)" }}>
            {opt.label}
            <div style={{ fontSize: 10.5, fontWeight: 500, marginTop: 2, color: opt.sel ? "var(--primary)" : "var(--text-dim)", opacity: opt.sel ? .8 : 1 }}>{opt.sub}</div>
          </div>
        ))}
      </div>
    </MiniShell>
  );
}

function MiniLoading() {
  const lines = [
    { text: "Analisando seu perfil", done: true },
    { text: "Definindo divisão semanal", done: true },
    { text: "Selecionando exercícios", done: true },
    { text: "Ajustando intensidade…", done: false },
  ];
  return (
    <MiniShell>
      <div style={{ padding: "22px 18px", display: "flex", flexDirection: "column", gap: 12, height: "100%" }}>
        <div style={{ width: 44, height: 44, borderRadius: "50%", border: `4px solid var(--bg-2)`, borderTopColor: "var(--primary)", animation: "spin .9s linear infinite", margin: "14px auto 8px" }} />
        <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
          {lines.map((l) => (
            <div key={l.text} style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 11.5, fontWeight: 600, color: l.done ? "var(--primary)" : "var(--text-dim)" }}>
              {l.done
                ? <svg style={{ width: 14, height: 14, flexShrink: 0 }} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><path d="M20 6L9 17l-5-5"/></svg>
                : <div style={{ width: 14, height: 14, flexShrink: 0, borderRadius: "50%", border: "1px solid var(--border)" }} />}
              {l.text}
            </div>
          ))}
        </div>
      </div>
    </MiniShell>
  );
}

function MiniActive() {
  return (
    <MiniShell>
      <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
        <div style={{ aspectRatio: "16/10", background: "linear-gradient(135deg, var(--surface-2), var(--bg-2))", display: "grid", placeItems: "center" }}>
          <svg style={{ width: 38, height: 38, stroke: "var(--text-dim)" }} viewBox="0 0 24 24" fill="none" strokeWidth="1.5"><path d="M6 8v8M18 8v8M4 10h2M18 10h2M6 12h12"/></svg>
        </div>
        <div style={{ padding: 13, display: "flex", flexDirection: "column", gap: 10, flex: 1 }}>
          <h4 style={{ fontFamily: "var(--font-display)", fontSize: 17, margin: 0, fontWeight: 800 }}>Bench Press</h4>
          <div style={{ display: "flex", gap: 7 }}>
            {[{ val: "4", l: "SÉRIES" }, { val: "10", l: "REPS" }, { val: "1", l: "ATUAL" }].map((c) => (
              <div key={c.l} style={{ flex: 1, background: "var(--bg-2)", borderRadius: 11, padding: 8, textAlign: "center" }}>
                <div style={{ fontFamily: "var(--font-display)", fontSize: 18, fontWeight: 800 }}>{c.val}</div>
                <div style={{ fontSize: 9, color: "var(--text-dim)" }}>{c.l}</div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: "auto", textAlign: "center", fontWeight: 800, fontSize: 13, padding: 13, borderRadius: 13, background: "var(--primary)", color: "var(--on-primary)", boxShadow: "var(--glow)" }}>
            Feito — série 1/4
          </div>
        </div>
      </div>
    </MiniShell>
  );
}

// ── Feature data ──────────────────────────────────────────────────────────────

const FEATURES = [
  { icon: "⚡", title: "Treino com IA", desc: "Responda algumas perguntas e a IA monta um plano sob medida pro seu objetivo, nível e rotina." },
  { icon: "🎯", title: "Personalizado de verdade", desc: "Cada exercício considera seu equipamento, local de treino e o que você gosta de fazer." },
  { icon: "🔥", title: "Engajamento que pega", desc: "Ofensivas, sequências e metas semanais pra você não largar no terceiro dia." },
  { icon: "🏠", title: "Academia ou em casa", desc: "Academia, peso corporal, ar livre — o plano se adapta a onde você está hoje." },
  { icon: "📊", title: "Evolução de verdade", desc: "Veja seus gráficos de carga, volume semanal e equilíbrio muscular na aba Progresso." },
  { icon: "💰", title: "Preço que cabe", desc: "A partir de R$9,90/mês no plano anual. Comece com 7 dias grátis, sem compromisso." },
];

const STEPS = [
  { num: "PASSO 01", title: "Conte seu objetivo", desc: "Objetivo, nível, dados físicos e o que você curte. Leva menos de um minuto.", phone: <MiniOnboarding /> },
  { num: "PASSO 02", title: "A IA monta seu plano", desc: "Em segundos, a EasyHealth gera uma divisão semanal completa com os exercícios certos.", phone: <MiniLoading /> },
  { num: "PASSO 03", title: "Treine e registre", desc: "Acompanhe séries, reps, descanso e carga. No fim, veja seu resumo e ofensiva.", phone: <MiniActive /> },
];

const TESTIMONIALS = [
  { name: "Lucas M.", role: "Musculação · 8 meses", stars: 5, text: "Larguei de usar planilha de Excel. A IA ajusta meu plano todo mês e eu só treino. Minha carga de supino subiu 30% em 6 meses." },
  { name: "Ana S.", role: "Treino em casa · 4 meses", stars: 5, text: "Achei que não dava pra treinar sério sem academia. O plano pra casa é completo, o coach responde na hora quando tenho dúvida de execução." },
  { name: "Rafael T.", role: "Corrida + força · 1 ano", stars: 5, text: "Uso pra misturar musculação e corrida. O histórico de evolução me motiva muito — consigo ver progresso de verdade semana a semana." },
];

// ── Shared section heading ────────────────────────────────────────────────────

function SecHead({ eyebrow, title, center = false }: { eyebrow: string; title: string; center?: boolean }) {
  return (
    <div style={{ marginBottom: 52, ...(center ? { textAlign: "center", maxWidth: "none" } : { maxWidth: "38ch" }) }}>
      <div style={{ fontSize: 12.5, fontWeight: 800, letterSpacing: ".16em", textTransform: "uppercase", color: "var(--primary)", marginBottom: 12 }}>
        {eyebrow}
      </div>
      <h2
        style={{ fontFamily: "var(--font-display)", fontSize: "clamp(31px, 4.6vw, 54px)", fontWeight: 700, letterSpacing: "-0.025em", lineHeight: 1.04, margin: 0 }}
        dangerouslySetInnerHTML={{ __html: title }}
      />
    </div>
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function LandingPage() {
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: "100svh", background: "var(--bg)", color: "var(--text)" }}>
      <AnalyticsTracker eventName="landing_view" conversionLabel={CONVERSIONS.PAGE_VIEW} />
      <AnalyticsTracker eventName="screen_view" params={{ screen_name: "home" }} />

      {/* ── NAV ── */}
      <LandingHeader />

      <main style={{ flex: 1 }}>
        {/* ── HERO ── */}
        <section style={{ position: "relative", overflow: "hidden", background: "radial-gradient(110% 100% at 100% 0%, oklch(0.34 0.10 258 / .8), transparent 55%), var(--bg)" }}>
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "clamp(48px, 7vw, 96px) clamp(16px, 4vw, 32px) clamp(56px, 7vw, 104px)", display: "grid", gridTemplateColumns: "1fr", gap: "clamp(30px, 5vw, 70px)", alignItems: "center" }}
            className="sm:grid-cols-[1.05fr_0.95fr]">
            {/* copy */}
            <div>
              {/* pill announce */}
              <div style={{ display: "inline-flex", alignItems: "center", gap: 9, marginBottom: 26, padding: "8px 15px 8px 9px", borderRadius: "var(--r-pill)", background: "var(--surface)", border: "1px solid var(--border)", fontSize: 13, fontWeight: 600, color: "var(--text-muted)" }}>
                <span style={{ width: 8, height: 8, borderRadius: "50%", background: "var(--primary)", boxShadow: "0 0 0 4px var(--primary-soft)" }} />
                <b style={{ color: "var(--text)", fontWeight: 700 }}>+300 treinos gerados</b> · Grátis por 7 dias
              </div>

              <h1 style={{ fontFamily: "var(--font-display)", fontSize: "clamp(40px, 6.4vw, 78px)", fontWeight: 700, letterSpacing: "-0.025em", lineHeight: 1.02, margin: "0 0 22px" }}>
                Treino com IA pra você evoluir com{" "}
                <span style={{ color: "var(--primary)" }}>constância</span>.
              </h1>

              <p style={{ fontSize: "clamp(17px, 1.4vw, 21px)", color: "var(--text-muted)", maxWidth: "30ch", margin: "0 0 32px", lineHeight: 1.5 }}>
                A EasyHealth monta seu plano, adapta a cada semana e te puxa pra treinar — do jeito que um personal faria, no seu bolso.
              </p>

              <div style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>
                <HeroCta />
                <a href="#funciona" style={{ display: "inline-flex", alignItems: "center", borderRadius: "var(--r-pill)", border: "1.5px solid var(--border-strong)", color: "var(--text)", fontSize: 17.5, fontWeight: 700, padding: "19px 34px", textDecoration: "none", transition: "border-color .2s" }}>
                  Ver como funciona
                </a>
              </div>

              <div style={{ marginTop: 18, fontSize: 13.5, color: "var(--text-dim)", display: "flex", alignItems: "center", gap: 8 }}>
                <svg style={{ width: 16, height: 16, flexShrink: 0 }} viewBox="0 0 24 24" fill="none" stroke="var(--good)" strokeWidth="2.5"><path d="M20 6L9 17l-5-5"/></svg>
                Sem cartão de crédito · Cancele quando quiser
              </div>
            </div>

            {/* phone */}
            <div style={{ display: "flex", justifyContent: "center" }}>
              <PhoneMockup />
            </div>
          </div>
        </section>

        {/* ── STATS ── */}
        <section style={{ borderTop: "1px solid var(--border)", borderBottom: "1px solid var(--border)", background: "var(--bg-2)" }}>
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "34px clamp(16px, 4vw, 32px)", display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 24 }}
            className="sm:grid-cols-4">
            {[
              { val: "+300", label: "treinos gerados" },
              { val: "IA", label: "adapta toda semana" },
              { val: "7 dias", label: "grátis pra testar" },
              { val: "R$9,90", label: "por mês no anual" },
            ].map((s) => (
              <div key={s.label} style={{ textAlign: "center" }}>
                <b style={{ display: "block", fontFamily: "var(--font-display)", fontSize: "clamp(28px, 3.4vw, 42px)", fontWeight: 800, letterSpacing: "-0.02em" }}>{s.val}</b>
                <span style={{ fontSize: 13, color: "var(--text-muted)", fontWeight: 600 }}>{s.label}</span>
              </div>
            ))}
          </div>
        </section>

        {/* ── FEATURES ── */}
        <section style={{ padding: "clamp(64px, 9vw, 120px) 0" }} id="recursos">
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <SecHead eyebrow="O que a EasyHealth faz por você" title="Um personal trainer que cabe no seu dia." />
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 18 }}>
              {FEATURES.map((f) => (
                <div key={f.title} className="landing-feat-card">
                  <div style={{ width: 48, height: 48, borderRadius: 13, display: "grid", placeItems: "center", marginBottom: 18, background: "var(--primary-soft)", fontSize: 24 }}>
                    {f.icon}
                  </div>
                  <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, letterSpacing: "-0.01em", margin: "0 0 8px" }}>{f.title}</h3>
                  <p style={{ color: "var(--text-muted)", fontSize: 15, margin: 0, lineHeight: 1.5 }}>{f.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── COMO FUNCIONA ── */}
        <section style={{ padding: "clamp(64px, 9vw, 120px) 0", background: "var(--bg-2)" }} id="funciona">
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <SecHead eyebrow="Como funciona na prática" title="Três passos até o primeiro treino." center />
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 26 }}>
              {STEPS.map((s) => (
                <div key={s.num} style={{ textAlign: "center" }}>
                  {s.phone}
                  <div style={{ fontSize: 12, fontWeight: 800, letterSpacing: ".12em", color: "var(--primary)", marginBottom: 8 }}>{s.num}</div>
                  <h3 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 700, letterSpacing: "-0.01em", margin: "0 0 8px" }}>{s.title}</h3>
                  <p style={{ color: "var(--text-muted)", fontSize: 14.5, lineHeight: 1.5, maxWidth: "28ch", margin: "0 auto" }}>{s.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── DEPOIMENTOS ── */}
        <section style={{ padding: "clamp(64px, 9vw, 120px) 0" }}>
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <SecHead eyebrow="O que dizem os usuários" title="Resultados reais de pessoas reais." center />
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: 18 }}>
              {TESTIMONIALS.map((t) => (
                <div key={t.name} style={{ border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: 26, background: "var(--surface)" }}>
                  <div style={{ color: "var(--primary)", letterSpacing: 2, fontSize: 15, marginBottom: 12 }}>{"★".repeat(t.stars)}</div>
                  <p style={{ fontSize: 16, lineHeight: 1.55, margin: "0 0 20px", color: "var(--text)" }}>&ldquo;{t.text}&rdquo;</p>
                  <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                    <div style={{ width: 44, height: 44, borderRadius: "50%", background: "var(--bg-2)", border: "1px solid var(--border)", display: "grid", placeItems: "center", fontSize: 16, flexShrink: 0 }}>
                      {t.name[0]}
                    </div>
                    <div>
                      <b style={{ display: "block", fontSize: 14.5 }}>{t.name}</b>
                      <small style={{ fontSize: 12.5, color: "var(--text-dim)" }}>{t.role}</small>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ── PRICING ── */}
        <section style={{ padding: "clamp(64px, 9vw, 120px) 0", background: "var(--bg-2)" }} id="planos">
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <SecHead eyebrow="Planos" title="Comece grátis. Continue se valer a pena." center />
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 20, maxWidth: 760, margin: "0 auto" }}>
              {/* Pro Mensal */}
              <div style={{ border: "1px solid var(--border)", borderRadius: "var(--r-xl)", padding: 30, background: "var(--surface)", display: "flex", flexDirection: "column" }}>
                <h3 style={{ fontFamily: "var(--font-display)", fontSize: 19, margin: "0 0 6px", fontWeight: 700 }}>Pro Mensal</h3>
                <div>
                  <span style={{ fontFamily: "var(--font-display)", fontSize: 44, fontWeight: 800, letterSpacing: "-0.02em" }}>R$ 19,90</span>
                  <small style={{ fontSize: 16, color: "var(--text-dim)", fontWeight: 600 }}>/mês</small>
                </div>
                <div style={{ fontSize: 13.5, color: "var(--text-dim)", marginTop: 4, marginBottom: 20 }}>Depois de 7 dias grátis</div>
                <PriceFeatures items={["Acesso completo a todos os recursos", "Treinos personalizados por IA", "Coach EasyHealth (IA)", "Histórico ilimitado"]} />
                <Link href="/sign-up" style={{ display: "flex", justifyContent: "center", borderRadius: "var(--r-pill)", border: "1.5px solid var(--border-strong)", color: "var(--text)", fontSize: 16, fontWeight: 700, padding: "16px 24px", textDecoration: "none", marginTop: "auto", transition: "border-color .15s" }}>
                  Começar 7 dias grátis
                </Link>
              </div>

              {/* Pro Anual */}
              <div style={{ border: "1.5px solid var(--primary)", borderRadius: "var(--r-xl)", padding: 30, background: "linear-gradient(140deg, var(--primary-soft), var(--surface))", display: "flex", flexDirection: "column", position: "relative", boxShadow: "var(--glow)" }}>
                <span style={{ position: "absolute", top: -13, left: "50%", transform: "translateX(-50%)", background: "linear-gradient(180deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", fontSize: 12, fontWeight: 800, padding: "6px 16px", borderRadius: 999, boxShadow: "var(--glow)", whiteSpace: "nowrap" }}>
                  ✦ Melhor valor
                </span>
                <h3 style={{ fontFamily: "var(--font-display)", fontSize: 19, margin: "0 0 6px", fontWeight: 700 }}>Pro Anual</h3>
                <div>
                  <span style={{ fontFamily: "var(--font-display)", fontSize: 44, fontWeight: 800, letterSpacing: "-0.02em", color: "var(--primary)" }}>R$ 9,90</span>
                  <small style={{ fontSize: 16, color: "var(--text-dim)", fontWeight: 600 }}>/mês</small>
                </div>
                <div style={{ fontSize: 14, color: "var(--primary)", fontWeight: 700, marginTop: 2 }}>R$ 118,80/ano · economize ~50%</div>
                <div style={{ height: 20 }} />
                <PriceFeatures items={["Tudo do Pro Mensal", "Metade do preço por mês", "7 dias grátis pra testar"]} highlight />
                <Link href="/sign-up" style={{ display: "flex", justifyContent: "center", borderRadius: "var(--r-pill)", background: "linear-gradient(180deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", fontSize: 16, fontWeight: 700, padding: "16px 24px", textDecoration: "none", marginTop: "auto", boxShadow: "var(--glow)" }}>
                  Começar 7 dias grátis
                </Link>
              </div>
            </div>
          </div>
        </section>

        {/* ── APP DOWNLOAD ── */}
        <section style={{ padding: "clamp(24px, 4vw, 48px) 0" }}>
          <div style={{ margin: "0 auto", maxWidth: 460, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <AppPromoCard placement="landing" />
          </div>
        </section>

        {/* ── FINAL CTA ── */}
        <section style={{ padding: "clamp(64px, 9vw, 120px) 0", textAlign: "center" }}>
          <div style={{ margin: "0 auto", maxWidth: 1180, padding: "0 clamp(16px, 4vw, 32px)" }}>
            <div style={{ borderRadius: "var(--r-xl)", padding: "clamp(46px, 7vw, 88px) 30px", background: "linear-gradient(150deg, var(--primary), var(--primary-2))", color: "var(--on-primary)", position: "relative", overflow: "hidden", boxShadow: "var(--glow)" }}>
              <h2 style={{ fontFamily: "var(--font-display)", fontSize: "clamp(30px, 4.6vw, 56px)", fontWeight: 700, letterSpacing: "-0.025em", lineHeight: 1.04, margin: "0 0 16px" }}>
                Comece hoje com 7 dias grátis.
              </h2>
              <p style={{ fontSize: 18, opacity: .9, margin: "0 0 30px" }}>
                Sem cartão de crédito pra começar. Cancele quando quiser.
              </p>
              <Link href="/sign-up" style={{ display: "inline-flex", alignItems: "center", borderRadius: "var(--r-pill)", background: "var(--bg)", color: "var(--text)", fontSize: 17.5, fontWeight: 700, padding: "19px 34px", textDecoration: "none", transition: "transform .18s" }}>
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

function PriceFeatures({ items, highlight = false }: { items: string[]; highlight?: boolean }) {
  return (
    <ul style={{ listStyle: "none", padding: 0, margin: "0 0 24px", display: "flex", flexDirection: "column", gap: 11 }}>
      {items.map((item) => (
        <li key={item} style={{ display: "flex", gap: 10, fontSize: 15, color: "var(--text-muted)", alignItems: "flex-start" }}>
          <svg style={{ width: 18, height: 18, flexShrink: 0, marginTop: 2, stroke: highlight ? "var(--primary)" : "var(--good)" }} viewBox="0 0 24 24" fill="none" strokeWidth="2.4"><path d="M20 6L9 17l-5-5"/></svg>
          {item}
        </li>
      ))}
    </ul>
  );
}
