"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { InsightCard } from "@/shared/components/workout/insight-card";
import "@/shared/components/workout/workout-ui.css";
import type { WorkoutSession } from "@/shared/types/workout";

// Ported from pro-charts.js
function lineChartSvg(vals: number[], w = 320, h = 150): string {
  if (vals.length < 2) return "";
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const rng = max - min || 1;
  const padX = 6, padTop = 14, padBot = 18;
  const pts = vals.map((v, i) => ({
    x: padX + (i / (vals.length - 1)) * (w - padX * 2),
    y: padTop + (1 - (v - min) / rng) * (h - padTop - padBot),
  }));
  const d = pts.map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" ");
  const last = pts[pts.length - 1];
  const area = `${d} L${last.x.toFixed(1)} ${h - padBot} L${pts[0].x.toFixed(1)} ${h - padBot} Z`;
  const id = `lg${Math.random().toString(36).slice(2, 7)}`;
  let grid = "";
  for (let g = 0; g < 3; g++) {
    const gy = padTop + (g / 2) * (h - padTop - padBot);
    grid += `<line x1="${padX}" y1="${gy.toFixed(1)}" x2="${w - padX}" y2="${gy.toFixed(1)}" stroke="var(--border)" stroke-width="1" stroke-dasharray="2 4"/>`;
  }
  const dots = pts.map((p, i) => {
    const isLast = i === pts.length - 1;
    return `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${isLast ? 4.5 : 3}" fill="${isLast ? "var(--primary)" : "var(--surface)"}" stroke="var(--primary)" stroke-width="2"/>`;
  }).join("");
  return `<svg viewBox="0 0 ${w} ${h}" width="100%" height="${h}" fill="none">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="var(--primary)" stop-opacity="0.3"/>
      <stop offset="1" stop-color="var(--primary)" stop-opacity="0"/>
    </linearGradient></defs>
    ${grid}
    <path d="${area}" fill="url(#${id})"/>
    <path d="${d}" stroke="var(--primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
    ${dots}
  </svg>`;
}

export default function ExerciseDetailPage() {
  const router = useRouter();
  const params = useSearchParams();
  const exerciseName = params.get("name") ?? "";

  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .get<{ sessions: WorkoutSession[] }>("/api/v1/workout_sessions")
      .then(({ sessions: s }) => setSessions(s))
      .finally(() => setLoading(false));
  }, []);

  const entries = useMemo(() => {
    const out: { date: Date; maxKg: number; sets: number; label: string }[] = [];
    for (const s of sessions) {
      const date = new Date(s.completed_at);
      for (const log of s.exercise_logs ?? []) {
        if (log.name.toLowerCase() !== exerciseName.toLowerCase()) continue;
        const ws = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
        const maxKg = Math.max(0, ...ws.filter((w): w is number => typeof w === "number" && w > 0));
        if (maxKg > 0) {
          out.push({
            date,
            maxKg,
            sets: log.sets,
            label: date.toLocaleDateString("pt-BR", { day: "numeric", month: "short" }),
          });
        }
      }
    }
    return out.sort((a, b) => a.date.getTime() - b.date.getTime());
  }, [sessions, exerciseName]);

  const weights = entries.map((e) => e.maxKg);
  const maxKg = weights.length ? Math.max(...weights) : 0;
  const firstKg = weights[0] ?? 0;
  const trend = firstKg > 0 ? Math.round(((maxKg - firstKg) / firstKg) * 100) : 0;
  const lastKg = weights[weights.length - 1] ?? 0;
  const prevKg = weights[weights.length - 2] ?? lastKg;
  const recentTrend = prevKg > 0 ? Math.round(((lastKg - prevKg) / prevKg) * 100) : 0;

  if (loading) return <LoadingScreen />;

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      {/* Header */}
      <header style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
        <button
          onClick={() => router.back()}
          aria-label="Voltar"
          style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "50%", width: 40, height: 40, display: "grid", placeItems: "center", cursor: "pointer", flexShrink: 0 }}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ width: 18, height: 18 }}>
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </button>
        <div style={{ minWidth: 0 }}>
          <h1 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {exerciseName}
          </h1>
          <p style={{ fontSize: 13, color: "var(--text-dim)", margin: 0 }}>Evolução de carga</p>
        </div>
      </header>

      {entries.length < 2 ? (
        <div style={{ textAlign: "center", padding: "60px 0" }}>
          <p style={{ fontSize: 32 }}>📊</p>
          <p style={{ color: "var(--text-muted)", marginTop: 12 }}>
            Dados insuficientes. Faça mais treinos com <strong>{exerciseName}</strong> para ver a evolução.
          </p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          {/* Metrics */}
          <div className="metric-grid">
            <div className="metric">
              <p className="mk">🏆 Recorde</p>
              <p className="mv primary">{maxKg}<small> kg</small></p>
              {trend > 0 && <p className="mtrend up">↑ {trend}% vs início</p>}
            </div>
            <div className="metric">
              <p className="mk">📈 Última sessão</p>
              <p className="mv">{lastKg}<small> kg</small></p>
              {recentTrend !== 0 && (
                <p className={`mtrend ${recentTrend > 0 ? "up" : "down"}`}>
                  {recentTrend > 0 ? "↑" : "↓"} {Math.abs(recentTrend)}% vs anterior
                </p>
              )}
            </div>
            <div className="metric">
              <p className="mk">🔁 Registros</p>
              <p className="mv">{entries.length}</p>
            </div>
            <div className="metric">
              <p className="mk">📦 Total séries</p>
              <p className="mv">{entries.reduce((s, e) => s + e.sets, 0)}</p>
            </div>
          </div>

          {/* Line chart */}
          <div className="chart-card">
            <p className="eyebrow" style={{ marginBottom: 12 }}>Evolução de carga</p>
            <div
              style={{ width: "100%", overflow: "hidden" }}
              dangerouslySetInnerHTML={{ __html: lineChartSvg(weights) }}
            />
            {/* X axis labels */}
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
              {[entries[0], entries[Math.floor(entries.length / 2)], entries[entries.length - 1]].map((e, i) => (
                <span key={i} style={{ fontSize: 11, color: "var(--text-dim)" }}>{e?.label}</span>
              ))}
            </div>
          </div>

          {/* AI Suggestion */}
          <InsightCard
            text={
              recentTrend > 0
                ? `Evolução excelente! <b>+${recentTrend}%</b> na última sessão. Tente manter a progressão nas próximas semanas — você está <b>acima da curva</b>.`
                : recentTrend < 0
                ? `Carga reduziu <b>${Math.abs(recentTrend)}%</b> na última sessão. Pode ser fadiga acumulada — considere <b>reduzir volume temporariamente</b>.`
                : `Carga estável em <b>${lastKg} kg</b>. Para progredir, tente adicionar <b>+1 repetição</b> ou <b>+2.5 kg</b> na próxima sessão.`
            }
          />

          {/* Session history for this exercise */}
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <p className="eyebrow" style={{ marginBottom: 4 }}>Sessões</p>
            {[...entries].reverse().map((e, i) => (
              <div
                key={i}
                style={{
                  display: "flex", alignItems: "center", justifyContent: "space-between",
                  background: "var(--surface)", border: "1px solid var(--border)",
                  borderRadius: "var(--r-md)", padding: "12px 14px",
                }}
              >
                <span style={{ fontSize: 13, color: "var(--text-muted)" }}>{e.label}</span>
                <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  <span style={{ fontSize: 12, color: "var(--text-dim)" }}>{e.sets} séries</span>
                  <span style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 16, color: "var(--primary)" }}>
                    {e.maxKg} kg
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
