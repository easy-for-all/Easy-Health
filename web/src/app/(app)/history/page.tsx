"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import { InsightCard } from "@/shared/components/workout/insight-card";
import "@/shared/components/workout/workout-ui.css";
import type { WorkoutSession } from "@/shared/types/workout";
import type { HealthProfile } from "@/shared/types/health-profile";

// ── Chart helpers (ported from pro-charts.js) ────────────────────────────────

function sparklineSvg(vals: number[], w = 72, h = 36): string {
  if (vals.length < 2) return "";
  const stroke = "var(--primary)";
  const pad = 3;
  const min = Math.min(...vals);
  const max = Math.max(...vals);
  const rng = max - min || 1;
  const pts = vals.map((v, i) => ({
    x: pad + (i / (vals.length - 1)) * (w - pad * 2),
    y: h - pad - ((v - min) / rng) * (h - pad * 2),
  }));
  const d = pts.map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" ");
  const last = pts[pts.length - 1];
  const id = `sg${Math.random().toString(36).slice(2, 7)}`;
  return `<svg viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" fill="none">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${stroke}" stop-opacity="0.28"/>
      <stop offset="1" stop-color="${stroke}" stop-opacity="0"/>
    </linearGradient></defs>
    <path d="${d} L${last.x.toFixed(1)} ${h} L${pts[0].x.toFixed(1)} ${h} Z" fill="url(#${id})"/>
    <path d="${d}" stroke="${stroke}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="${last.x.toFixed(1)}" cy="${last.y.toFixed(1)}" r="2.6" fill="${stroke}"/>
  </svg>`;
}

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
    const last = i === pts.length - 1;
    return `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="${last ? 4.5 : 3}" fill="${last ? "var(--primary)" : "var(--surface)"}" stroke="var(--primary)" stroke-width="2"/>`;
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

// ── Data helpers ──────────────────────────────────────────────────────────────

type ExerciseProgress = {
  name: string;
  muscleGroup: string | null;
  weights: number[];
  count: number; // number of records
  maxKg: number;
  trend: number; // % change vs prev
};

function computeDailyMinutes(sessions: WorkoutSession[], days = 7): { label: string; mins: number }[] {
  const now = new Date();
  const dayNames = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
  return Array.from({ length: days }, (_, i) => {
    const day = new Date(now);
    day.setDate(day.getDate() - (days - 1 - i));
    day.setHours(0, 0, 0, 0);
    const dayEnd = new Date(day);
    dayEnd.setDate(dayEnd.getDate() + 1);
    const mins = sessions
      .filter((s) => { const d = new Date(s.completed_at); return d >= day && d < dayEnd; })
      .reduce((sum, s) => sum + (s.duration_minutes ?? 0), 0);
    return { label: dayNames[day.getDay()], mins };
  });
}

// Expected minutes per day based on user health profile
function computeExpectedMinutes(profile: HealthProfile | null): number {
  if (!profile) return 30;
  let base = 30;
  if (profile.fitness_level === "advanced") base += 15;
  else if (profile.fitness_level === "intermediate") base += 7;
  if (profile.goal === "lose_weight") base += 10;
  if (profile.goal === "gain_muscle") base += 5;
  if (profile.age && profile.age < 30) base += 5;
  if (profile.age && profile.age > 60) base -= 5;
  const daysPerWeek = profile.training_days_per_week ?? 3;
  const activityFactor = daysPerWeek / 7;
  return Math.round(base * activityFactor + base * 0.3);
}

const MUSCLE_NAME_MAP: Record<string, string> = {
  chest: "Peito", peitoral: "Peito", peito: "Peito",
  back: "Costas", costas: "Costas", dorsal: "Costas",
  legs: "Pernas", pernas: "Pernas", quadriceps: "Pernas", "quadríceps": "Pernas",
  shoulders: "Ombros", ombros: "Ombros", ombro: "Ombros",
  biceps: "Bíceps", "bíceps": "Bíceps", bicep: "Bíceps",
  triceps: "Tríceps", "tríceps": "Tríceps", tricep: "Tríceps",
  core: "Core", abdomen: "Core", abdominal: "Core", abs: "Core",
  glutes: "Glúteos", "glúteos": "Glúteos", gluteos: "Glúteos",
  calves: "Panturrilha", panturrilha: "Panturrilha",
  cardio: "Cardio",
};

function normalizeMuscleGroup(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const lower = raw.toLowerCase().trim();
  if (lower === "n/a" || lower === "null" || lower === "-") return null;
  return MUSCLE_NAME_MAP[lower] ?? (raw.charAt(0).toUpperCase() + raw.slice(1));
}

function computeMuscleBalance(sessions: WorkoutSession[]): { name: string; pct: number; sets: number; low: boolean }[] {
  const counts: Record<string, number> = {};
  for (const s of sessions) {
    for (const log of s.exercise_logs ?? []) {
      const normalized = normalizeMuscleGroup(log.muscle_group);
      if (!normalized || normalized.toLowerCase() === "outros") continue;
      counts[normalized] = (counts[normalized] ?? 0) + log.sets;
    }
  }
  if (Object.keys(counts).length === 0) return [];
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const max = Math.max(1, ...Object.values(counts));
  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 7)
    .map(([name, sets]) => ({
      name,
      sets,
      pct: Math.round((sets / max) * 100),
      low: (sets / total) < 0.10,
    }));
}

function computeExerciseProgress(sessions: WorkoutSession[]): ExerciseProgress[] {
  const map: Record<string, { name: string; muscleGroup: string | null; entries: { date: Date; maxKg: number }[] }> = {};
  for (const s of sessions) {
    const date = new Date(s.completed_at);
    for (const log of s.exercise_logs ?? []) {
      const key = log.name.toLowerCase();
      if (!map[key]) map[key] = { name: log.name, muscleGroup: log.muscle_group ?? null, entries: [] };
      const allWeights = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
      const warmupFlags: boolean[] = (log as { is_warmup_by_set?: boolean[] }).is_warmup_by_set ?? [];
      const weights = allWeights.filter((_, i) => !warmupFlags[i]);
      const maxKg = Math.max(0, ...weights.filter((w): w is number => typeof w === "number" && w > 0));
      if (maxKg > 0) map[key].entries.push({ date, maxKg });
    }
  }
  return Object.values(map)
    .filter((e) => e.entries.length >= 2)
    .map((e) => {
      const sorted = [...e.entries].sort((a, b) => a.date.getTime() - b.date.getTime());
      const weights = sorted.map((x) => x.maxKg);
      const maxKg = Math.max(...weights);
      const prev = weights[weights.length - 2] ?? maxKg;
      const trend = prev > 0 ? Math.round(((maxKg - prev) / prev) * 100) : 0;
      return { name: e.name, muscleGroup: e.muscleGroup, weights, count: sorted.length, maxKg, trend };
    })
    .sort((a, b) => b.count - a.count)
    .slice(0, 12);
}

function computeStreak(sessions: WorkoutSession[]): number {
  if (!sessions.length) return 0;
  const sorted = [...sessions].sort((a, b) =>
    new Date(b.completed_at).getTime() - new Date(a.completed_at).getTime()
  );
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  let streak = 0;
  let cursor = new Date(today);
  for (const s of sorted) {
    const d = new Date(s.completed_at);
    d.setHours(0, 0, 0, 0);
    const diff = Math.round((cursor.getTime() - d.getTime()) / 86400000);
    if (diff === 0 || diff === 1) {
      streak++;
      cursor = d;
    } else break;
  }
  return streak;
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function HistoryPage() {
  return <UpgradeGate><HistoryContent /></UpgradeGate>;
}

type Tab = "resumo" | "cargas" | "historico";

function HistoryContent() {
  const router = useRouter();
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [healthProfile, setHealthProfile] = useState<HealthProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("resumo");
  const [selected, setSelected] = useState<WorkoutSession | null>(null);

  useEffect(() => {
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "historico" });
    Promise.all([
      api.get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions"),
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
    ]).then(([sessionsData, profile]) => {
      setSessions(sessionsData.sessions);
      setHealthProfile(profile);
    }).finally(() => setLoading(false));
  }, []);

  const dailyMins = useMemo(() => computeDailyMinutes(sessions), [sessions]);
  const muscleBalance = useMemo(() => computeMuscleBalance(sessions), [sessions]);
  const exerciseProgress = useMemo(() => computeExerciseProgress(sessions), [sessions]);
  const streak = useMemo(() => computeStreak(sessions), [sessions]);

  const totalVol = useMemo(
    () =>
      sessions.reduce((sum, s) =>
        sum + (s.exercise_logs ?? []).reduce((sv, log) => {
          const ws = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
          const rs = Array.isArray(log.reps) ? (log.reps as number[]) : Array.from({ length: log.sets }, () => log.reps as number);
          return sv + ws.reduce<number>((lv, w, i) => lv + (w ?? 0) * (rs[i] ?? 0), 0);
        }, 0), 0),
    [sessions]
  );

  const thisWeekSessions = useMemo(() => {
    const now = new Date();
    const weekStart = new Date(now);
    weekStart.setDate(now.getDate() - now.getDay());
    weekStart.setHours(0, 0, 0, 0);
    return sessions.filter((s) => new Date(s.completed_at) >= weekStart).length;
  }, [sessions]);

  const expectedMins = useMemo(() => computeExpectedMinutes(healthProfile), [healthProfile]);
  const maxDayMins = Math.max(1, ...dailyMins.map((d) => d.mins));
  const chartMaxY = Math.max(maxDayMins, Math.ceil(expectedMins * 1.25));

  if (loading) return <LoadingScreen />;

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      {/* Header */}
      <header style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 26, fontWeight: 700, letterSpacing: "-0.02em", margin: 0 }}>
          Progresso
        </h1>
        <span style={{ fontSize: 13, color: "var(--text-dim)" }}>{sessions.length} treinos</span>
      </header>

      {/* Tabs */}
      <div className="seg-tabs" style={{ marginBottom: 20 }}>
        {(["resumo", "cargas", "historico"] as Tab[]).map((t) => (
          <button key={t} className={tab === t ? "on" : ""} onClick={() => setTab(t)}>
            {t === "resumo" ? "Resumo" : t === "cargas" ? "Cargas" : "Histórico"}
          </button>
        ))}
      </div>

      {/* ── RESUMO ── */}
      {tab === "resumo" && (
        <motion.div
          key="resumo"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.22 }}
          style={{ display: "flex", flexDirection: "column", gap: 14 }}
        >
          {/* Metrics */}
          <div className="metric-grid">
            <div className="metric">
              <p className="mk">🏋️ Treinos</p>
              <p className="mv primary">{sessions.length}<small> total</small></p>
              <p className="mtrend up">↑ {thisWeekSessions} esta semana</p>
            </div>
            <div className="metric">
              <p className="mk">🔥 Ofensiva</p>
              <p className="mv good">{streak}<small> dias</small></p>
              <p className="mtrend">{streak > 0 ? "em sequência" : "sem sequência"}</p>
            </div>
            <div className="metric">
              <p className="mk">⚖️ Volume total</p>
              <p className="mv">{totalVol >= 1000 ? `${(totalVol / 1000).toFixed(1)}` : totalVol}<small> {totalVol >= 1000 ? "t" : "kg"}</small></p>
            </div>
            <div className="metric">
              <p className="mk">📅 Esta semana</p>
              <p className="mv">{thisWeekSessions}<small> treinos</small></p>
            </div>
          </div>

          {/* Daily minutes bar chart */}
          {dailyMins.some((d) => d.mins > 0) && (
            <div className="chart-card">
              <div className="chead">
                <div>
                  <p className="eyebrow">Minutos por dia</p>
                  <p className="cv" style={{ fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 26 }}>
                    {maxDayMins > 0 ? `${maxDayMins} min` : "—"}
                    <small style={{ fontSize: 14, color: "var(--text-dim)", fontWeight: 600 }}> melhor dia</small>
                  </p>
                </div>
              </div>

              {/* Chart with Y-axis */}
              <div style={{ display: "flex", gap: 8, alignItems: "flex-end", marginBottom: 6 }}>
                {/* Y-axis labels */}
                <div style={{ display: "flex", flexDirection: "column", justifyContent: "space-between", height: 110, flexShrink: 0, paddingBottom: 20 }}>
                  <span style={{ fontSize: 9, color: "var(--text-dim)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>{chartMaxY}</span>
                  <span style={{ fontSize: 9, color: "var(--text-dim)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>{Math.round(chartMaxY / 2)}</span>
                  <span style={{ fontSize: 9, color: "var(--text-dim)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>0</span>
                </div>

                {/* Bars container with expected average line */}
                <div style={{ flex: 1, position: "relative" }}>
                  {/* Expected average dashed line */}
                  <div
                    style={{
                      position: "absolute",
                      left: 0,
                      right: 0,
                      bottom: `calc(20px + ${(expectedMins / chartMaxY) * 90}px)`,
                      height: 0,
                      borderTop: "1.5px dashed var(--hot, #ef4444)",
                      opacity: 0.8,
                      zIndex: 2,
                      pointerEvents: "none",
                    }}
                  />
                  <div className="bars" style={{ position: "relative", zIndex: 1 }}>
                    {dailyMins.map((d, i) => (
                      <div key={i} className="bar" title={d.mins > 0 ? `${d.label}: ${d.mins}min (meta: ${expectedMins}min, ${d.mins >= expectedMins ? "+" : ""}${d.mins - expectedMins}min)` : `${d.label}: sem treino`}>
                        <motion.div
                          className={`bcol ${d.mins === 0 ? "muted" : ""}`}
                          initial={{ height: 0 }}
                          animate={{ height: d.mins > 0 ? `${Math.max(8, (d.mins / chartMaxY) * 90)}%` : "8%" }}
                          transition={{ duration: 0.5, delay: i * 0.06, ease: "easeOut" }}
                        />
                        <span className="blab">{d.label}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* Legend */}
              <div style={{ display: "flex", gap: 16, marginTop: 8, flexWrap: "wrap" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                  <div style={{ width: 12, height: 12, borderRadius: 3, background: "linear-gradient(180deg, var(--primary), var(--primary-2))", flexShrink: 0 }} />
                  <span style={{ fontSize: 11, color: "var(--text-dim)" }}>Minutos realizados</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
                  <div style={{ width: 16, height: 0, borderTop: "1.5px dashed var(--hot, #ef4444)", flexShrink: 0 }} />
                  <span style={{ fontSize: 11, color: "var(--text-dim)" }}>Média esperada ({expectedMins}min)</span>
                </div>
              </div>
            </div>
          )}

          {/* Muscle balance */}
          {muscleBalance.length > 0 ? (
            <div className="chart-card">
              <p className="eyebrow" style={{ marginBottom: 14 }}>Equilíbrio muscular</p>
              <div className="mbar">
                {muscleBalance.map(({ name, pct, low }) => (
                  <div key={name} className="mb">
                    <span className="mbn" style={{ display: "flex", alignItems: "center", gap: 4 }}>
                      {name}
                      {low && <span style={{ fontSize: 9, background: "var(--hot-soft)", color: "var(--hot)", borderRadius: 4, padding: "1px 5px", fontWeight: 700 }}>baixo</span>}
                    </span>
                    <div className="mbt">
                      <motion.i
                        className={low ? "low" : ""}
                        initial={{ width: 0 }}
                        animate={{ width: `${pct}%` }}
                        transition={{ duration: 0.6, ease: "easeOut" }}
                      />
                    </div>
                    <span className="mbv">{pct}%</span>
                  </div>
                ))}
              </div>
              {/* Insight */}
              {(() => {
                const top = muscleBalance.slice(0, 2).map((m) => m.name);
                const lowGroups = muscleBalance.filter((m) => m.low).map((m) => m.name);
                if (lowGroups.length > 0) {
                  return (
                    <p style={{ fontSize: 12, color: "var(--text-dim)", marginTop: 12, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
                      Foco em <strong>{top.join(" e ")}</strong>. {lowGroups.join(", ")} teve{lowGroups.length > 1 ? "m" : ""} menor volume.
                    </p>
                  );
                }
                return (
                  <p style={{ fontSize: 12, color: "var(--text-dim)", marginTop: 12, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
                    Grupo mais treinado: <strong>{top[0]}</strong>{top[1] ? ` e ${top[1]}` : ""}.
                  </p>
                );
              })()}
            </div>
          ) : sessions.length >= 2 ? (
            <div className="chart-card" style={{ textAlign: "center", padding: "20px" }}>
              <p className="eyebrow" style={{ marginBottom: 8 }}>Equilíbrio muscular</p>
              <p style={{ fontSize: 13, color: "var(--text-muted)" }}>
                Ainda não há dados suficientes para calcular equilíbrio muscular. Complete mais treinos para acompanhar sua evolução.
              </p>
            </div>
          ) : null}

          {/* AI Insight */}
          {sessions.length >= 3 && (
            <InsightCard
              text={`Você treinou <b>${thisWeekSessions}x esta semana</b>. ${
                streak > 1
                  ? `Sua ofensiva de <b>${streak} dias</b> está ativa!`
                  : "Continue para manter a consistência."
              } ${muscleBalance[0] ? `Grupo mais trabalhado: <b>${muscleBalance[0].name}</b>.` : ""}`}
            />
          )}
        </motion.div>
      )}

      {/* ── CARGAS ── */}
      {tab === "cargas" && (
        <motion.div
          key="cargas"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.22 }}
          style={{ display: "flex", flexDirection: "column", gap: 8 }}
        >
          {exerciseProgress.length === 0 ? (
            <div style={{ textAlign: "center", padding: "40px 0" }}>
              <p style={{ fontSize: 32 }}>📊</p>
              <p style={{ color: "var(--text-muted)", marginTop: 12 }}>
                Faça pelo menos 2 treinos com o mesmo exercício para ver a evolução de carga.
              </p>
            </div>
          ) : (
            exerciseProgress.map((ex) => (
              <button
                key={ex.name}
                className="exprog"
                onClick={() => router.push(`/history/exercise?name=${encodeURIComponent(ex.name)}`)}
              >
                <div className="epi">
                  <b>{ex.name}</b>
                  <div className="epm">{ex.muscleGroup ?? "exercício"} · {ex.count} reg.</div>
                </div>
                <div
                  className="epspark"
                  dangerouslySetInnerHTML={{ __html: sparklineSvg(ex.weights) }}
                />
                <div className="epval">
                  <b>{ex.maxKg} kg</b>
                  {ex.trend !== 0 && (
                    <span style={{ color: ex.trend > 0 ? "var(--good)" : "var(--hot)" }}>
                      {ex.trend > 0 ? "↑" : "↓"}{Math.abs(ex.trend)}%
                    </span>
                  )}
                </div>
              </button>
            ))
          )}
        </motion.div>
      )}

      {/* ── HISTÓRICO ── */}
      {tab === "historico" && (
        <motion.div
          key="historico"
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.22 }}
        >
          {sessions.length === 0 ? (
            <div style={{ textAlign: "center", padding: "40px 0" }}>
              <p style={{ fontSize: 32 }}>📋</p>
              <p style={{ color: "var(--text-muted)", marginTop: 12 }}>Nenhum treino registrado ainda.</p>
            </div>
          ) : (
            <div className="timeline">
              {sessions.map((s, i) => {
                const d = new Date(s.completed_at);
                const dateStr = d.toLocaleDateString("pt-BR", { weekday: "short", day: "numeric", month: "short" });
                return (
                  <button
                    key={s.id}
                    className="tl-item"
                    style={{ background: "none", border: "none", cursor: "pointer", textAlign: "left", padding: "0 0 18px", width: "100%" }}
                    onClick={() => setSelected(s)}
                  >
                    <div className="tdot done">
                      <svg viewBox="0 0 24 24"><path d="M20 6L9 17l-5-5" /></svg>
                    </div>
                    <div className="tbody">
                      <div className="tt">
                        <b>{s.workout_day_name}</b>
                        <span className="tdate">{dateStr}</span>
                      </div>
                      <div className="tmeta">
                        {s.duration_minutes} min
                        {s.exercise_logs?.length ? ` · ${s.exercise_logs.length} exercícios` : ""}
                        {s.fatigue_level ? ` · cansaço ${s.fatigue_level}/5` : ""}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </motion.div>
      )}

      {/* Session detail modal */}
      {selected && (
        <SessionSheet session={selected} onClose={() => setSelected(null)} />
      )}
    </div>
  );
}

// ── Session detail bottom sheet ───────────────────────────────────────────────

function SessionSheet({ session, onClose }: { session: WorkoutSession; onClose: () => void }) {
  const logs = session.exercise_logs ?? [];
  const date = new Date(session.completed_at).toLocaleDateString("pt-BR", {
    weekday: "long", day: "numeric", month: "long",
  });

  const totalVol = logs.reduce((sum, log) => {
    const ws = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
    const rs = Array.isArray(log.reps) ? (log.reps as number[]) : Array.from({ length: log.sets }, () => log.reps as number);
    return sum + ws.reduce<number>((sv, w, i) => sv + (w ?? 0) * (rs[i] ?? 0), 0);
  }, 0);

  return (
    <div
      style={{ position: "fixed", inset: 0, zIndex: 50, background: "rgba(0,0,0,.6)", backdropFilter: "blur(4px)" }}
      onClick={onClose}
    >
      <motion.div
        style={{
          position: "absolute", bottom: 0, left: 0, right: 0,
          maxHeight: "88svh", overflowY: "auto",
          background: "var(--bg-2)",
          borderRadius: "var(--r-xl) var(--r-xl) 0 0",
          paddingBottom: 32,
        }}
        onClick={(e) => e.stopPropagation()}
        initial={{ y: "100%" }}
        animate={{ y: 0 }}
        exit={{ y: "100%" }}
        transition={{ duration: 0.38, ease: [0.22, 1, 0.36, 1] }}
        role="dialog"
        aria-label={session.workout_day_name}
      >
        {/* Grabber */}
        <div style={{ padding: "12px 0 0", display: "flex", justifyContent: "center" }}>
          <div style={{ width: 40, height: 4, borderRadius: 9, background: "var(--border-strong)" }} />
        </div>

        {/* Header */}
        <div style={{ padding: "14px 20px 16px", borderBottom: "1px solid var(--border)" }}>
          <h2 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: "0 0 4px" }}>
            {session.workout_day_name}
          </h2>
          <p style={{ fontSize: 13, color: "var(--text-dim)", margin: 0, textTransform: "capitalize" }}>{date}</p>
        </div>

        {/* Stats */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10, padding: "14px 20px" }}>
          {[
            { label: "minutos", val: String(session.duration_minutes), cls: "primary" },
            { label: "volume",  val: totalVol > 0 ? `${(totalVol / 1000).toFixed(1)}t` : "—", cls: "good" },
            { label: "exercícios", val: String(logs.filter((l) => l.sets > 0).length), cls: "" },
          ].map(({ label, val, cls }) => (
            <div key={label} className="dstat" style={cls === "primary" ? { background: "var(--primary-soft)" } : cls === "good" ? { background: "var(--good-soft)" } : { background: "var(--bg-2)" }}>
              <b style={{ color: cls === "primary" ? "var(--primary)" : cls === "good" ? "var(--good)" : "var(--text)" }}>{val}</b>
              <span>{label}</span>
            </div>
          ))}
        </div>

        {/* Exercise list */}
        <div style={{ display: "flex", flexDirection: "column", gap: 8, padding: "0 20px" }}>
          {logs.map((log, idx) => {
            const ws = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
            const rs = Array.isArray(log.reps) ? (log.reps as number[]) : Array.from({ length: log.sets }, () => log.reps as number);
            return (
              <div key={`${session.id}-${log.workout_day_exercise_id}`} style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-md)", padding: "12px 14px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                  <span style={{ width: 22, height: 22, borderRadius: "50%", background: "var(--primary-soft)", color: "var(--primary)", display: "grid", placeItems: "center", fontSize: 11, fontWeight: 700, flexShrink: 0 }}>
                    {idx + 1}
                  </span>
                  <span style={{ fontWeight: 700, fontSize: 14 }}>{log.name}</span>
                </div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                  {Array.from({ length: log.sets }, (_, i) => (
                    <span key={i} style={{ background: "var(--bg-2)", border: "1px solid var(--border)", borderRadius: "var(--r-sm)", padding: "4px 10px", fontSize: 12 }}>
                      <b style={{ color: "var(--primary)" }}>S{i + 1}</b>{" "}
                      {ws[i] ? `${ws[i]} kg` : "—"} × {rs[i] ?? "—"}
                    </span>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </motion.div>
    </div>
  );
}
