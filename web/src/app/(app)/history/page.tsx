"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutSession } from "@/shared/types/workout";

export default function HistoryPage() {
  const [sessions, setSessions] = useState<WorkoutSession[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);

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
            <div key={s.id} className="rounded-xl border border-gray-100 bg-white p-4">
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
                <span className="rounded-full bg-gray-100 px-3 py-1 text-sm text-gray-600">
                  {s.duration_minutes} min
                </span>
              </div>
              {s.fatigue_level && (
                <p className="mt-2 text-xs font-medium text-orange-500">Cansaço {s.fatigue_level}/5</p>
              )}
              {s.exercise_logs?.length ? (
                <div className="mt-3 space-y-1">
                  {s.exercise_logs.map((log) => (
                    <p key={`${s.id}-${log.workout_day_exercise_id}`} className="text-xs text-gray-500">
                      {log.name}: {log.weight_kg ? `${log.weight_kg} kg` : "sem peso registrado"}
                    </p>
                  ))}
                </div>
              ) : null}
              {s.notes && <p className="mt-2 text-sm text-gray-500">{s.notes}</p>}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
