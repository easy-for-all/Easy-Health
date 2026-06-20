"use client";

/* ============================================================
   EasyHealth — telas de execução por ENGINE (fiel ao protótipo)
   Cardio contínuo · Intervalado · Recuperação

   Componentes APRESENTACIONAIS: recebem valores + callbacks.
   Usam os tokens CSS do app (--bg, --primary, --text...) e
   framer-motion (já presente no projeto).

   Coloque em: app/workout/today/workout-engine-screens.tsx
   ============================================================ */

import { motion } from "framer-motion";

/* cores de fase (mesma linguagem do protótipo) */
const C = {
  work: "var(--hot)",          // trabalho / esforço
  rest: "oklch(0.72 0.17 158)",// descanso / recuperação (verde)
  warm: "oklch(0.80 0.14 80)", // aquecimento (âmbar)
  primary: "var(--primary)",
};

function mmss(total: number) {
  const s = Math.max(0, Math.round(total));
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

/* anel de progresso reutilizável */
function Ring({ pct, size = 240, stroke = 12, color }: { pct: number; size?: number; stroke?: number; color: string }) {
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const off = circ * (1 - Math.max(0, Math.min(100, pct)) / 100);
  return (
    <svg width={size} height={size} style={{ position: "absolute", inset: 0, transform: "rotate(-90deg)" }}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--border)" strokeWidth={stroke} />
      <motion.circle
        cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round"
        strokeDasharray={circ} animate={{ strokeDashoffset: off }} transition={{ duration: 0.6, ease: "easeOut" }}
        style={{ filter: `drop-shadow(0 0 8px ${color})` }}
      />
    </svg>
  );
}

/* card de métrica (rótulo + valor grande) */
function Metric({ k, v, unit }: { k: string; v: string | number; unit?: string }) {
  return (
    <div style={{ border: "1px solid var(--border)", borderRadius: "var(--r-md, 14px)", background: "var(--surface)", padding: "14px 15px" }}>
      <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: ".04em", textTransform: "uppercase", color: "var(--text-dim, #6b7280)" }}>{k}</p>
      <p style={{ fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 26, marginTop: 6, fontVariantNumeric: "tabular-nums", color: "var(--text)" }}>
        {v}{unit ? <small style={{ fontSize: 13, color: "var(--text-dim, #6b7280)", fontWeight: 600, marginLeft: 2 }}>{unit}</small> : null}
      </p>
    </div>
  );
}

function NextRow({ nextName }: { nextName: string | null }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 11, borderRadius: "var(--r-md, 14px)", background: "var(--bg-2)", border: "1px solid var(--border)", padding: "13px 15px" }}>
      <div>
        <p style={{ fontSize: 10.5, fontWeight: 800, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--text-dim, #6b7280)" }}>Próximo</p>
        <p style={{ fontSize: 14.5, fontWeight: 700, marginTop: 1, color: "var(--text)" }}>{nextName ?? "Fim do treino"}</p>
      </div>
      <span style={{ marginLeft: "auto", color: "var(--text-dim, #6b7280)" }}>→</span>
    </div>
  );
}

/* ============================================================
   1) CARDIO CONTÍNUO — corrida / caminhada / bike rua / cardio
   ============================================================ */
export function CardioPanel({
  exerciseName, nextName, secondsLeft, totalSeconds, intensity, durationMin, blockIndex, blockTotal,
}: {
  exerciseName: string;
  nextName: string | null;
  secondsLeft: number;
  totalSeconds: number;
  intensity?: string | null;
  durationMin?: number | null;
  blockIndex: number;
  blockTotal: number;
}) {
  const pct = totalSeconds > 0 ? (1 - secondsLeft / totalSeconds) * 100 : 0;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16, flex: 1 }}>
      {/* barra fina de progresso */}
      <div style={{ height: 6, borderRadius: 9, background: "var(--bg-2)", overflow: "hidden" }}>
        <motion.div animate={{ width: `${pct}%` }} transition={{ duration: 0.5 }} style={{ height: "100%", background: `linear-gradient(90deg, var(--primary), var(--hot))`, borderRadius: 9 }} />
      </div>

      {/* relógio gigante */}
      <div style={{ textAlign: "center", padding: "8px 0 2px" }}>
        <p style={{ fontSize: 11.5, fontWeight: 800, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--text-dim, #6b7280)" }}>Tempo restante</p>
        <p style={{ fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 78, lineHeight: 1, letterSpacing: "-.03em", fontVariantNumeric: "tabular-nums", marginTop: 6, color: "var(--text)" }}>
          {mmss(secondsLeft)}
        </p>
      </div>

      {/* bloco atual */}
      <div style={{ borderRadius: "var(--r-md, 16px)", padding: "16px 18px", background: "linear-gradient(150deg, var(--primary-soft), var(--surface))", border: "1px solid var(--primary)" }}>
        <p style={{ fontSize: 11, fontWeight: 800, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--primary)" }}>Bloco atual</p>
        <p style={{ fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 23, marginTop: 4, color: "var(--text)" }}>{exerciseName}</p>
        <p style={{ fontSize: 13.5, color: "var(--text-muted)", marginTop: 4 }}>Bloco {blockIndex} de {blockTotal}</p>
      </div>

      <NextRow nextName={nextName} />

      {/* métricas contextuais */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
        <Metric k="Intensidade" v={intensity ?? "Moderada"} />
        <Metric k="Duração" v={durationMin ?? Math.round(totalSeconds / 60)} unit="min" />
      </div>
    </div>
  );
}

/* ============================================================
   2) INTERVALADO — HIIT / Funcional / Bike spinning
   ============================================================ */
export function IntervalPanel({
  exerciseName, nextName, secondsLeft, totalSeconds, blockIndex, blockTotal,
}: {
  exerciseName: string;
  nextName: string | null;
  secondsLeft: number;
  totalSeconds: number;
  blockIndex: number;
  blockTotal: number;
}) {
  const pct = totalSeconds > 0 ? (secondsLeft / totalSeconds) * 100 : 0;
  const phase = C.work;
  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, gap: 14 }}>
      <p style={{ textAlign: "center", fontSize: 13, fontWeight: 800, letterSpacing: ".1em", textTransform: "uppercase", color: "var(--text-muted)" }}>
        Bloco <b style={{ color: phase }}>{blockIndex}</b> de {blockTotal}
      </p>
      <p style={{ textAlign: "center", fontFamily: "var(--font-display, inherit)", fontWeight: 800, fontSize: 34, letterSpacing: ".02em", textTransform: "uppercase", color: phase, lineHeight: 1 }}>
        Trabalho
      </p>

      {/* anel + tempo */}
      <div style={{ flex: 1, display: "grid", placeItems: "center", position: "relative", minHeight: 240 }}>
        <div style={{ position: "relative", width: 240, height: 240, display: "grid", placeItems: "center" }}>
          <Ring pct={pct} size={240} stroke={12} color={phase} />
          <p style={{ fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 80, lineHeight: 1, letterSpacing: "-.03em", fontVariantNumeric: "tabular-nums", color: "var(--text)", zIndex: 1 }}>
            {mmss(secondsLeft)}
          </p>
        </div>
      </div>

      <p style={{ textAlign: "center", fontSize: 16, fontWeight: 700, color: "var(--text)" }}>{exerciseName}</p>

      {/* pontos de progresso */}
      <div style={{ display: "flex", justifyContent: "center", gap: 6, flexWrap: "wrap" }}>
        {Array.from({ length: blockTotal }, (_, i) => (
          <span key={i} style={{
            width: 9, height: 9, borderRadius: "50%",
            background: i < blockIndex - 1 ? phase : "var(--bg-2)",
            border: `1px solid ${i === blockIndex - 1 ? phase : "var(--border)"}`,
            boxShadow: i === blockIndex - 1 ? `0 0 0 3px var(--hot-soft, rgba(249,115,22,.2))` : "none",
          }} />
        ))}
      </div>

      <NextRow nextName={nextName} />
    </div>
  );
}

/* ============================================================
   3) RECUPERAÇÃO — mobilidade / alongamento / isometria
   ============================================================ */
export function RecoveryPanel({
  exerciseName, nextName, imageUrl, gifUrl, instruction, side,
  elapsedSeconds, targetSeconds, running, onToggle, breathing = true, onOpenMedia,
}: {
  exerciseName: string;
  nextName: string | null;
  imageUrl?: string | null;
  gifUrl?: string | null;
  instruction?: string | null;
  side?: string | null;
  elapsedSeconds: number;
  targetSeconds: number;
  running: boolean;
  onToggle: () => void;
  breathing?: boolean;
  onOpenMedia?: () => void;
}) {
  const pct = targetSeconds > 0 ? Math.min(100, (elapsedSeconds / targetSeconds) * 100) : 0;
  const media = gifUrl || imageUrl;
  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, gap: 15 }}>
      {/* mídia grande */}
      <div onClick={onOpenMedia} style={{ position: "relative", borderRadius: 20, overflow: "hidden", aspectRatio: "4 / 3", cursor: media ? "pointer" : "default", background: "var(--bg-2)" }}>
        {media ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={media} alt={exerciseName} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        ) : (
          <div style={{ width: "100%", height: "100%", display: "grid", placeItems: "center", color: "var(--text-dim, #6b7280)", fontSize: 13 }}>sem imagem</div>
        )}
        {side ? (
          <span style={{ position: "absolute", top: 12, left: 12, fontSize: 11, fontWeight: 700, background: "rgba(0,0,0,.45)", backdropFilter: "blur(8px)", color: "#fff", padding: "5px 11px", borderRadius: 999 }}>{side}</span>
        ) : null}
      </div>

      <p style={{ textAlign: "center", fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 24, color: "var(--text)" }}>{exerciseName}</p>

      {/* anel de tempo-alvo */}
      <div style={{ display: "grid", placeItems: "center", position: "relative", height: 176 }}>
        <div style={{ position: "relative", width: 176, height: 176, display: "grid", placeItems: "center" }}>
          <Ring pct={pct} size={176} stroke={10} color={C.rest} />
          <div style={{ textAlign: "center", zIndex: 1 }}>
            <p style={{ fontFamily: "var(--font-display, inherit)", fontWeight: 700, fontSize: 40, lineHeight: 1, fontVariantNumeric: "tabular-nums", color: "var(--text)" }}>{mmss(elapsedSeconds)}</p>
            <p style={{ fontSize: 11, color: "var(--text-dim, #6b7280)", marginTop: 2 }}>meta {mmss(targetSeconds)}</p>
          </div>
        </div>
      </div>

      {/* respiração */}
      {breathing && (
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
          <motion.div
            animate={{ scale: [0.62, 1, 0.62], opacity: [0.65, 1, 0.65] }}
            transition={{ duration: 8, repeat: Infinity, ease: "easeInOut" }}
            style={{ width: 52, height: 52, borderRadius: "50%", background: `radial-gradient(circle at 40% 35%, oklch(0.85 0.10 158), ${C.rest})` }}
          />
          <span style={{ fontSize: 12, fontWeight: 700, color: "var(--text-muted)" }}>Inspire… expire…</span>
        </div>
      )}

      {instruction ? (
        <p style={{ textAlign: "center", fontSize: 14.5, color: "var(--text-muted)", lineHeight: 1.5, maxWidth: 300, margin: "0 auto" }}>{instruction}</p>
      ) : null}

      {/* iniciar / pausar */}
      <div style={{ display: "flex", justifyContent: "center" }}>
        <button onClick={onToggle} style={{
          border: running ? "1px solid var(--border)" : 0,
          background: running ? "var(--surface)" : "var(--primary)",
          color: running ? "var(--text-muted)" : "#fff",
          borderRadius: 999, padding: "10px 28px", fontSize: 14, fontWeight: 700, cursor: "pointer",
        }}>
          {running ? "Pausar" : elapsedSeconds === 0 ? "Iniciar" : "Continuar"}
        </button>
      </div>

      <NextRow nextName={nextName} />
    </div>
  );
}
