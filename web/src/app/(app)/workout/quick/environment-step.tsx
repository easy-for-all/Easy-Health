"use client";

/* ============================================================
   EasyHealth — Ambiente + Equipamentos + Ramificações
   (fiel ao protótipo). O ambiente MUDA a experiência:
   - equipamentos sugeridos mudam por modalidade + local
   - corrida/bike em casa perguntam se tem esteira/bike
   - sem o equipamento, sugere trocar de modalidade
   ============================================================ */

import { motion } from "framer-motion";
import type { Modality } from "./modality-picker";

export type Location = "academia" | "casa" | "ar_livre";
export type EquipId =
  | "nenhum" | "halteres" | "kettlebell" | "faixa" | "corda"
  | "esteira" | "bike_ergo" | "bike_rua" | "banco" | "caixa" | "colchonete";

const LOCATIONS: { value: Location; label: string; emoji: string; desc: string }[] = [
  { value: "academia", label: "Academia",    emoji: "🏋️", desc: "Aparelhos, barras e máquinas" },
  { value: "casa",     label: "Em casa",      emoji: "🏠", desc: "Pouco ou nenhum equipamento" },
  { value: "ar_livre", label: "Ao ar livre",  emoji: "🌳", desc: "Parques, ruas e quadras" },
];

const EQUIP_LABEL: Record<EquipId, string> = {
  nenhum: "Nenhum", halteres: "Halteres", kettlebell: "Kettlebell", faixa: "Faixa elástica",
  corda: "Corda", esteira: "Esteira", bike_ergo: "Bike ergométrica", bike_rua: "Bike outdoor",
  banco: "Banco", caixa: "Caixa", colchonete: "Colchonete",
};

// equipamentos sugeridos por modalidade + local
const MATRIX: Partial<Record<Modality, Record<Location, EquipId[]>>> = {
  corrida:    { academia: ["esteira"],              casa: ["esteira"],                       ar_livre: ["nenhum"] },
  caminhada:  { academia: ["esteira"],              casa: ["nenhum", "esteira"],             ar_livre: ["nenhum"] },
  bike:       { academia: ["bike_ergo"],            casa: ["bike_ergo"],                     ar_livre: ["bike_rua"] },
  cardio:     { academia: ["esteira","bike_ergo","corda"], casa: ["corda","nenhum"],         ar_livre: ["corda","nenhum"] },
  funcional:  { academia: ["kettlebell","corda","caixa","halteres","banco"], casa: ["halteres","faixa","colchonete","nenhum"], ar_livre: ["nenhum","corda","caixa"] },
  mobilidade: { academia: ["faixa","colchonete"],   casa: ["colchonete","nenhum"],           ar_livre: ["nenhum"] },
  alongamento:{ academia: ["faixa","colchonete"],   casa: ["colchonete","nenhum"],           ar_livre: ["nenhum"] },
  musculacao: { academia: ["halteres","banco","kettlebell"], casa: ["halteres","faixa","banco"], ar_livre: ["nenhum","faixa"] },
};

// ramificação condicional (esteira? / bike?) + sugestão de troca
type Branch = { key: "hasTreadmill" | "hasBike"; q: string; yes: string; no: string; swapMsg: string; swapTo: Modality[] };
function branchFor(modality: Modality, location: Location): Branch | null {
  if (modality === "corrida" && location === "casa")
    return { key: "hasTreadmill", q: "Você tem esteira em casa?", yes: "Sim, tenho esteira", no: "Não tenho",
             swapMsg: "Sem esteira, corrida em casa não rende. Que tal trocar?", swapTo: ["funcional", "caminhada"] };
  if (modality === "bike" && location === "casa")
    return { key: "hasBike", q: "Você tem bike ergométrica em casa?", yes: "Sim, tenho bike", no: "Não tenho",
             swapMsg: "Sem bike, a gente adapta pra outra modalidade.", swapTo: ["funcional", "corrida"] };
  return null;
}

// "o que muda" — foco por ambiente
const FOCUS: Partial<Record<Modality, Record<Location, string[]>>> = {
  corrida:    { academia: ["velocidade","inclinação","tempo"], casa: ["velocidade","tempo"], ar_livre: ["ritmo","distância","vel. média"] },
  bike:       { academia: ["tempo","RPM","intensidade"], casa: ["tempo","RPM"], ar_livre: ["distância","vel. média","percurso"] },
  funcional:  { academia: ["kettlebell","corda","caixa"], casa: ["peso corporal","pouco espaço"], ar_livre: ["saltos","deslocamentos"] },
  mobilidade: { academia: ["faixas","acessórios"], casa: ["tapete","movimentos guiados"], ar_livre: ["sem equipamento"] },
};

const MODALITY_LABEL: Record<Modality, string> = {
  musculacao: "Musculação", cardio: "Cardio", corrida: "Corrida", caminhada: "Caminhada",
  bike: "Bike", funcional: "Funcional", mobilidade: "Mobilidade", alongamento: "Alongamento", ai_choice: "IA escolhe",
};

export function EnvironmentStep({
  modality, location, equipment, branchAnswer,
  onLocation, onToggleEquip, onBranch, onSwapModality,
}: {
  modality: Modality;
  location: Location | null;
  equipment: EquipId[];
  branchAnswer: boolean | null;
  onLocation: (l: Location) => void;
  onToggleEquip: (e: EquipId) => void;
  onBranch: (v: boolean) => void;
  onSwapModality: (m: Modality) => void;
}) {
  const branch = location ? branchFor(modality, location) : null;
  const focus = (location && FOCUS[modality]?.[location]) || [];
  const equipIds = (location && MATRIX[modality]?.[location]) || ["nenhum"];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
      {/* ambiente */}
      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        {LOCATIONS.map((l) => {
          const sel = location === l.value;
          return (
            <motion.button key={l.value} whileTap={{ scale: 0.98 }} onClick={() => onLocation(l.value)}
              style={{ display: "flex", alignItems: "center", gap: 12, width: "100%", borderRadius: "var(--r-md)",
                border: `2px solid ${sel ? "var(--primary)" : "var(--border)"}`, padding: "14px 16px", textAlign: "left",
                background: sel ? "var(--primary-soft)" : "var(--surface)", color: "var(--text)", cursor: "pointer" }}>
              <span style={{ fontSize: 24 }}>{l.emoji}</span>
              <span style={{ flex: 1 }}>
                <b style={{ fontSize: 15, fontWeight: 700 }}>{l.label}</b>
                <span style={{ display: "block", fontSize: 12.5, color: "var(--text-muted)" }}>{l.desc}</span>
              </span>
              {sel && <span style={{ color: "var(--primary)" }}>✓</span>}
            </motion.button>
          );
        })}
      </div>

      {/* contexto: o que muda */}
      {focus.length > 0 && (
        <div style={{ borderRadius: "var(--r-sm)", background: "var(--bg-2)", border: "1px solid var(--hairline)", padding: "13px 15px" }}>
          <p style={{ fontSize: 12, fontWeight: 700, color: "var(--text-muted)" }}>
            ✦ <b style={{ color: "var(--text)" }}>{MODALITY_LABEL[modality]} · {LOCATIONS.find(x=>x.value===location)?.label}</b> muda o foco do treino
          </p>
          <div style={{ display: "flex", gap: 7, flexWrap: "wrap", marginTop: 10 }}>
            {focus.map((f) => (
              <span key={f} style={{ fontSize: 12, fontWeight: 600, color: "var(--text-muted)", background: "var(--surface)", border: "1px solid var(--border)", padding: "4px 10px", borderRadius: 999 }}>{f}</span>
            ))}
          </div>
        </div>
      )}

      {/* ramificação condicional */}
      {branch && (
        <div style={{ borderRadius: "var(--r-md)", border: "1px solid var(--border)", background: "var(--surface)", padding: "16px 17px" }}>
          <p style={{ fontSize: 15, fontWeight: 700, margin: "0 0 12px", display: "flex", gap: 9, alignItems: "center" }}>
            <span style={{ width: 30, height: 30, borderRadius: 9, background: "var(--primary-soft)", color: "var(--primary)", display: "grid", placeItems: "center", flex: "none" }}>?</span>
            {branch.q}
          </p>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 9 }}>
            <button onClick={() => onBranch(true)} style={ynStyle(branchAnswer === true)}>{branch.yes}</button>
            <button onClick={() => onBranch(false)} style={ynStyle(branchAnswer === false)}>{branch.no}</button>
          </div>
          {branchAnswer === false && (
            <div style={{ marginTop: 12, borderRadius: "var(--r-sm)", padding: "14px 15px", background: "var(--warn-soft)", border: "1px solid color-mix(in oklab, var(--warn) 30%, transparent)" }}>
              <p style={{ fontSize: 13, color: "var(--text)", margin: "0 0 11px", lineHeight: 1.45 }}>{branch.swapMsg}</p>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                {branch.swapTo.map((m) => (
                  <button key={m} onClick={() => onSwapModality(m)} style={{ border: "1px solid var(--border-strong)", background: "var(--surface)", color: "var(--text)", borderRadius: 999, padding: "8px 13px", fontSize: 13, fontWeight: 700, cursor: "pointer" }}>
                    {MODALITY_LABEL[m]}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* equipamentos — adaptativos */}
      <div>
        <p style={{ fontSize: 11.5, fontWeight: 800, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--text-dim)", marginBottom: 10 }}>
          Quais equipamentos você tem?
        </p>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 9 }}>
          {dedupe(equipIds).map((id) => {
            const sel = equipment.includes(id);
            return (
              <button key={id} onClick={() => onToggleEquip(id)}
                style={{ display: "flex", alignItems: "center", gap: 10, borderRadius: "var(--r-sm)",
                  border: `1.5px solid ${sel ? "var(--primary)" : "var(--border)"}`, background: sel ? "var(--primary-soft)" : "var(--surface)",
                  color: "var(--text)", padding: "12px 13px", cursor: "pointer", textAlign: "left" }}>
                <b style={{ flex: 1, fontSize: 14, fontWeight: 700 }}>{EQUIP_LABEL[id]}</b>
                {sel && <span style={{ color: "var(--primary)" }}>✓</span>}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function ynStyle(sel: boolean): React.CSSProperties {
  return {
    border: `1.5px solid ${sel ? "var(--primary)" : "var(--border)"}`, borderRadius: "var(--r-sm)",
    background: sel ? "var(--primary-soft)" : "var(--bg-2)", color: "var(--text)", fontWeight: 700, fontSize: 14,
    padding: "13px 10px", cursor: "pointer",
  };
}
function dedupe(ids: EquipId[]): EquipId[] {
  const out = [...new Set(ids)];
  if (!out.includes("nenhum") && out.length < 4) out.push("nenhum");
  return out;
}
