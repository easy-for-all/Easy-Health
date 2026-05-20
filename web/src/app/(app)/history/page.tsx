"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import type { WorkoutSession } from "@/shared/types/workout";

export default function HistoryPage() {
  return <UpgradeGate><HistoryContent /></UpgradeGate>;
}

const FEELING_LABELS: Record<string, string> = {
  bem: "Bem", cansado: "Cansado", dolorido: "Dolorido", pesado: "Pesado", dor: "Com dor",
};
const FEELING_COLORS: Record<string, string> = {
  bem: "text-green-600 bg-green-50 border-green-200",
  cansado: "text-yellow-600 bg-yellow-50 border-yellow-200",
  dolorido: "text-orange-600 bg-orange-50 border-orange-200",
  pesado: "text-red-600 bg-red-50 border-red-200",
  dor: "text-red-700 bg-red-100 border-red-300",
};

function calcVolume(weights: Array<number | null>, reps: number[]): number {
  return weights.reduce<number>((sum, w, i) => sum + (w ?? 0) * (reps[i] ?? 0), 0);
}

function formatMinutes(totalSeconds: number): string {
  if (!totalSeconds) return "—";
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return m > 0 ? `${m}min ${s}s` : `${s}s`;
}

function SessionDetailModal({ session, onClose }: { session: WorkoutSession; onClose: () => void }) {
  const logs = session.exercise_logs ?? [];
  const date = new Date(session.completed_at).toLocaleDateString("pt-BR", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  });
  const time = new Date(session.completed_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

  const totalVolume = logs.reduce((sum, log) => {
    const weights = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
    const repsArr = Array.isArray(log.reps) ? log.reps : Array.from({ length: log.sets }, () => log.reps as number);
    return sum + calcVolume(weights, repsArr);
  }, 0);

  const completedExercises = logs.filter((l) => l.sets > 0).length;
  const skippedExercises = logs.filter((l) => l.planned_sets != null && l.sets < l.planned_sets).length;

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/60" onClick={onClose}>
      <div
        className="max-h-[92vh] w-full overflow-y-auto rounded-t-2xl bg-white pb-10"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Handle */}
        <div className="sticky top-0 bg-white pt-3 pb-2 px-4 border-b border-gray-100">
          <div className="mb-2 mx-auto h-1 w-10 rounded-full bg-gray-200" />
          <h2 className="text-lg font-bold text-gray-900">{session.workout_day_name}</h2>
          <p className="text-xs text-gray-400 capitalize">{date} às {time}</p>
        </div>

        {/* Summary stats */}
        <div className="px-4 pt-3 pb-3 grid grid-cols-3 gap-2">
          <div className="rounded-xl bg-primary-50 p-3 text-center">
            <p className="text-xl font-bold text-primary-600">{session.duration_minutes}</p>
            <p className="text-xs text-primary-400 mt-0.5">minutos</p>
          </div>
          <div className="rounded-xl bg-green-50 p-3 text-center">
            <p className="text-xl font-bold text-green-600">{totalVolume > 0 ? `${(totalVolume / 1000).toFixed(1)}t` : "—"}</p>
            <p className="text-xs text-green-400 mt-0.5">volume</p>
          </div>
          <div className="rounded-xl bg-gray-50 p-3 text-center">
            <p className="text-xl font-bold text-gray-700">{completedExercises}</p>
            <p className="text-xs text-gray-400 mt-0.5">exercícios</p>
          </div>
        </div>

        {session.fatigue_level && (
          <div className="mx-4 mb-3 flex items-center gap-2">
            <span className="text-xs text-gray-500">Cansaço geral:</span>
            <div className="flex gap-1">
              {[1,2,3,4,5].map((n) => (
                <div key={n} className={`h-2 w-6 rounded-full ${n <= session.fatigue_level! ? "bg-orange-400" : "bg-gray-100"}`} />
              ))}
            </div>
            <span className="text-xs font-medium text-orange-500">{session.fatigue_level}/5</span>
          </div>
        )}

        {skippedExercises > 0 && (
          <div className="mx-4 mb-3 rounded-lg bg-amber-50 border border-amber-200 px-3 py-2 text-xs text-amber-700">
            {skippedExercises} exercício(s) com séries puladas
          </div>
        )}

        {session.notes && (
          <p className="mx-4 mb-3 rounded-lg bg-gray-50 px-3 py-2 text-sm text-gray-600 italic">"{session.notes}"</p>
        )}

        {/* Exercise list */}
        <div className="px-4 space-y-3">
          {logs.map((log, idx) => {
            const skipped = log.planned_sets != null && log.sets < log.planned_sets;
            const weights = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
            const repsArr = Array.isArray(log.reps) ? log.reps : Array.from({ length: log.sets }, () => log.reps as number);
            const exVolume = calcVolume(weights, repsArr);
            const feelingColor = log.feeling ? FEELING_COLORS[log.feeling] ?? "text-gray-500 bg-white border-gray-200" : null;

            return (
              <div key={`${session.id}-${log.workout_day_exercise_id}`} className="rounded-xl border border-gray-100 bg-gray-50 p-3">
                {/* Header */}
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary-100 text-xs font-bold text-primary-600">
                      {idx + 1}
                    </span>
                    <p className="text-sm font-semibold text-gray-900">{log.name}</p>
                  </div>
                  <div className="flex flex-col items-end gap-1">
                    {log.feeling && log.feeling !== "nao_informado" && feelingColor && (
                      <span className={`rounded-full border px-2 py-0.5 text-xs font-medium ${feelingColor}`}>
                        {FEELING_LABELS[log.feeling] ?? log.feeling}
                      </span>
                    )}
                    {exVolume > 0 && (
                      <span className="text-xs text-gray-400">{exVolume} kg vol.</span>
                    )}
                  </div>
                </div>

                {/* Skipped notice */}
                {skipped && (
                  <div className="mb-2 flex items-center gap-1.5 text-xs text-amber-600">
                    <span>⚠</span>
                    <span>{log.sets} de {log.planned_sets} séries realizadas</span>
                  </div>
                )}

                {/* Set chips */}
                <div className="flex flex-wrap gap-1.5">
                  {Array.from({ length: log.sets }, (_, i) => (
                    <span key={i} className="rounded-lg bg-white border border-gray-200 px-2 py-1.5 text-xs text-gray-700">
                      <span className="font-semibold text-primary-600">S{i + 1}</span>
                      {" "}
                      {weights[i] ? `${weights[i]} kg` : "—"}
                      {" × "}
                      {repsArr[i] ?? "—"}
                    </span>
                  ))}
                </div>

                {/* Rest time */}
                {log.rest_seconds ? (
                  <p className="mt-1.5 text-xs text-gray-400">Descanso: {formatMinutes(log.rest_seconds)}</p>
                ) : null}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function HistoryContent() {
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<WorkoutSession | null>(null);

  useEffect(() => {
    api.get<{ sessions: WorkoutSession[]; total: number }>("/api/v1/workout_sessions")
      .then(({ sessions: s, total: t }) => { setSessions(s); setTotal(t); })
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <LoadingScreen />;

  return (
    <div className="min-h-screen px-4 py-6">
      <div className="mb-6 flex items-center gap-3">
        <Link href="/dashboard" className="text-sm text-gray-400 hover:text-gray-600">←</Link>
        <h1 className="text-xl font-bold text-gray-900">Histórico</h1>
        <span className="ml-auto text-sm text-gray-400">{total} treinos</span>
      </div>

      {sessions.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <p className="text-4xl">📋</p>
          <p className="mt-3 text-gray-500">Nenhum treino registrado ainda.</p>
          <Link href="/workout/today" className="mt-4 text-sm font-medium text-primary-600 hover:underline">
            Fazer meu primeiro treino
          </Link>
        </div>
      ) : (
        <div className="space-y-3">
          {sessions.map((s) => (
            <button
              key={s.id}
              onClick={() => setSelected(s)}
              className="w-full rounded-xl border border-gray-100 bg-white p-4 text-left active:bg-gray-50"
            >
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-semibold text-gray-900">{s.workout_day_name}</p>
                  <p className="text-sm text-gray-400">
                    {new Date(s.completed_at).toLocaleDateString("pt-BR", {
                      weekday: "short",
                      day: "numeric",
                      month: "short",
                    })}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <span className="rounded-full bg-gray-100 px-3 py-1 text-sm text-gray-600">
                    {s.duration_minutes} min
                  </span>
                  <span className="text-gray-300 text-sm">›</span>
                </div>
              </div>
              {s.fatigue_level && (
                <p className="mt-2 text-xs font-medium text-orange-500">Cansaço {s.fatigue_level}/5</p>
              )}
              {s.exercise_logs?.length ? (
                <p className="mt-1 text-xs text-gray-400">{s.exercise_logs.length} exercícios</p>
              ) : null}
            </button>
          ))}
        </div>
      )}

      {selected && <SessionDetailModal session={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}
