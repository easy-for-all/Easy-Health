"use client";

/* ============================================================
   EasyHealth — Picker de modalidade AGRUPADO (fiel ao protótipo)
   Substitui a lista plana do passo 1 do /workout/quick.
   Usa os tokens Lumen que já existem no globals.css.
   ============================================================ */

import { motion } from "framer-motion";

export type Modality =
  | "musculacao" | "cardio" | "corrida" | "caminhada" | "bike"
  | "funcional" | "mobilidade" | "alongamento" | "ai_choice";

type Item = { value: Modality; label: string; emoji: string; desc: string; engine: string };
type Group = { group: string; tint: string; items: Item[] };

const GROUPS: Group[] = [
  { group: "Força", tint: "var(--primary)", items: [
    { value: "musculacao", label: "Musculação", emoji: "🏋️", desc: "Séries, repetições e carga", engine: "Força" },
  ]},
  { group: "Cardio", tint: "var(--cool)", items: [
    { value: "corrida",   label: "Corrida",   emoji: "🏃", desc: "Ritmo, distância e intervalos", engine: "Cardio" },
    { value: "caminhada", label: "Caminhada", emoji: "🚶", desc: "Contínua, no seu ritmo",        engine: "Cardio" },
    { value: "bike",      label: "Bike",      emoji: "🚴", desc: "Spinning, ergométrica ou rua",  engine: "Cardio" },
    { value: "cardio",    label: "Cardio",    emoji: "💓", desc: "Condicionamento geral",         engine: "Cardio" },
  ]},
  { group: "Performance", tint: "var(--hot)", items: [
    { value: "funcional", label: "Funcional", emoji: "⚡", desc: "Circuitos e HIIT", engine: "Intervalado" },
  ]},
  { group: "Recuperação", tint: "var(--good)", items: [
    { value: "mobilidade",  label: "Mobilidade",  emoji: "🤸", desc: "Amplitude e articulações", engine: "Recuperação" },
    { value: "alongamento", label: "Alongamento", emoji: "🧘", desc: "Flexibilidade guiada",     engine: "Recuperação" },
  ]},
  { group: "Inteligente", tint: "var(--primary)", items: [
    { value: "ai_choice", label: "IA escolhe", emoji: "🤖", desc: "A IA monta o melhor formato pra hoje", engine: "Adaptativo" },
  ]},
];

export function ModalityPicker({
  value, onSelect,
}: {
  value: Modality | null;
  onSelect: (m: Modality) => void;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
      {GROUPS.map((g) => (
        <div key={g.group}>
          <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 10 }}>
            <span style={{ fontSize: 12, fontWeight: 800, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--text)" }}>{g.group}</span>
            <span style={{ fontSize: 10.5, fontWeight: 700, color: g.tint, background: "color-mix(in oklab, " + g.tint + " 16%, transparent)", padding: "3px 9px", borderRadius: 999 }}>
              {g.items[0].engine}
            </span>
            <span style={{ flex: 1, height: 1, background: "var(--border)" }} />
          </div>

          <div style={{ display: "grid", gridTemplateColumns: g.items.length === 1 ? "1fr" : "1fr 1fr", gap: 10 }}>
            {g.items.map((m) => {
              const sel = value === m.value;
              const ai = m.value === "ai_choice";
              return (
                <motion.button
                  key={m.value}
                  whileTap={{ scale: 0.985 }}
                  onClick={() => onSelect(m.value)}
                  style={{
                    position: "relative", textAlign: "left", cursor: "pointer", color: "var(--text)",
                    border: `1.5px solid ${sel ? g.tint : "var(--border)"}`,
                    borderRadius: "var(--r-md)",
                    background: sel
                      ? `linear-gradient(150deg, color-mix(in oklab, ${g.tint} 16%, transparent), var(--surface))`
                      : ai ? `linear-gradient(150deg, var(--primary-soft), var(--surface))` : "var(--surface)",
                    padding: "15px 15px 14px", display: "flex", flexDirection: "column", gap: 10, overflow: "hidden",
                  }}
                >
                  <span style={{
                    position: "absolute", top: 13, right: 13, width: 22, height: 22, borderRadius: "50%",
                    border: `2px solid ${sel ? g.tint : "var(--border-strong)"}`, background: sel ? g.tint : "transparent",
                    display: "grid", placeItems: "center",
                  }}>
                    {sel && (
                      <svg viewBox="0 0 24 24" fill="none" stroke="var(--on-primary)" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" style={{ width: 12, height: 12 }}>
                        <path d="M20 6L9 17l-5-5" />
                      </svg>
                    )}
                  </span>
                  <span style={{
                    width: 44, height: 44, borderRadius: 13, display: "grid", placeItems: "center", fontSize: 22,
                    background: ai
                      ? `radial-gradient(circle at 36% 30%, oklch(0.88 0.10 var(--accent-h)), var(--primary) 46%, var(--primary-2) 82%)`
                      : sel ? `color-mix(in oklab, ${g.tint} 16%, transparent)` : "var(--bg-2)",
                  }}>{m.emoji}</span>
                  <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 16.5, letterSpacing: "-.01em" }}>{m.label}</span>
                  <span style={{ fontSize: 12, color: "var(--text-muted)", lineHeight: 1.4 }}>{m.desc}</span>
                  <span style={{ marginTop: 2, fontSize: 10, fontWeight: 700, letterSpacing: ".06em", textTransform: "uppercase", color: "var(--text-dim)", display: "inline-flex", alignItems: "center", gap: 5 }}>
                    <span style={{ width: 6, height: 6, borderRadius: "50%", background: g.tint }} /> {m.engine}
                  </span>
                </motion.button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}
