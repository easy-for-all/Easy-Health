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

function SessionDetailModal({ session, onClose }: { session: WorkoutSession; onClose: () => void }) {
  const logs = session.exercise_logs ?? [];
  const date = new Date(session.completed_at).toLocaleDateString("pt-BR", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  });
  const time = new Date(session.completed_at).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={onClose}>
      <div
        className="max-h-[90vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-10 pt-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-3 mx-auto h-1 w-10 rounded-full bg-gray-200" />
        <div className="mb-4">
          <h2 className="text-lg font-bold text-gray-900">{session.workout_day_name}</h2>
          <p className="text-xs text-gray-400 capitalize">{date} às {time}</p>
          <div className="mt-2 flex gap-3 text-xs text-gray-500">
            <span>{session.duration_minutes} min</span>
            {session.fatigue_level && <span className="text-orange-500">Cansaço {session.fatigue_level}/5</span>}
          </div>
          {session.notes && <p className="mt-2 rounded-lg bg-gray-50 px-3 py-2 text-sm text-gray-600">{session.notes}</p>}
        </div>

        <div className="space-y-3">
          {logs.map((log) => {
            const skipped = log.planned_sets != null && log.sets < log.planned_sets;
            const weights = log.weight_by_set ?? (log.weight_kg ? [log.weight_kg] : []);
            const repsArr = Array.isArray(log.reps) ? log.reps : Array.from({ length: log.sets }, () => log.reps as number);
            return (
              <div key={`${session.id}-${log.workout_day_exercise_id}`} className="rounded-xl border border-gray-100 bg-gray-50 p-3">
                <div className="flex items-center justify-between mb-1">
                  <p className="text-sm font-semibold text-gray-900">{log.name}</p>
                  {log.feeling && log.feeling !== "nao_informado" && (
                    <span className="rounded-full bg-white px-2 py-0.5 text-xs text-gray-500 border border-gray-200">
                      {FEELING_LABELS[log.feeling] ?? log.feeling}
                    </span>
                  )}
                </div>
                {skipped && (
                  <p className="text-xs text-amber-600 mb-1">{log.sets} feitas / {(log.planned_sets ?? 0) - log.sets} puladas</p>
                )}
                <div className="flex flex-wrap gap-1.5">
                  {Array.from({ length: log.sets }, (_, i) => (
                    <span key={i} className="rounded-lg bg-white border border-gray-200 px-2 py-1 text-xs text-gray-600">
                      S{i + 1}: {weights[i] ? `${weights[i]} kg` : "—"} × {repsArr[i] ?? "—"} reps
                    </span>
                  ))}
                </div>
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
