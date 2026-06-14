"use client";

import Link from "next/link";
import type { WorkoutSession } from "@/shared/types/workout";
import type { WorkoutDay } from "@/shared/types/workout";
import "./workout-ui.css";

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
  forearms: "Antebraços", calves: "Panturrilhas", glutes: "Glúteos", trapezius: "Trapézio",
};

type WorkoutDoneCardProps = {
  session: WorkoutSession;
  suggestedDay?: WorkoutDay | null;
};

const CONGRATS = [
  "Excelente trabalho hoje!",
  "Consistência é tudo. Continue!",
  "Mais um treino no bolso.",
  "Você é mais forte do que ontem.",
  "Treino concluído. Missão cumprida.",
];

export function WorkoutDoneCard({ session, suggestedDay }: WorkoutDoneCardProps) {
  const congrats = CONGRATS[session.id % CONGRATS.length];
  const isDifferentFromSuggested = suggestedDay &&
    session.workout_day_id !== suggestedDay.id &&
    session.workout_day_name !== suggestedDay.name;
  const sessionMuscles = [...new Set(
    (session.exercise_logs ?? [])
      .map((l) => (l as { muscle_group?: string | null }).muscle_group)
      .filter((m): m is string => !!m)
  )];

  return (
    <div className="workout-done-card">
      <div className="wdc-top">
        <span className="wdc-badge">✓ Treino realizado hoje</span>
      </div>

      <h2 className="wdc-name">{session.workout_day_name}</h2>
      <p className="wdc-congrats">{congrats}</p>
      {sessionMuscles.length > 0 ? (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 5, margin: "4px 0 8px" }}>
          {sessionMuscles.slice(0, 4).map((m) => (
            <span key={m} className="tag-chip muscle">{MUSCLE_LABELS[m] ?? m}</span>
          ))}
        </div>
      ) : null}

      <div className="wdc-meta">
        {session.duration_minutes > 0 && (
          <div className="m">
            <b>{session.duration_minutes}</b>
            <span>minutos</span>
          </div>
        )}
        {session.calories_estimated && session.calories_estimated > 0 && (
          <div className="m">
            <b>{session.calories_estimated}</b>
            <span>kcal est.</span>
          </div>
        )}
        {(session.exercise_logs?.length ?? 0) > 0 && (
          <div className="m">
            <b>{session.exercise_logs!.length}</b>
            <span>exercícios</span>
          </div>
        )}
      </div>

      {isDifferentFromSuggested && (
        <p className="wdc-note">
          Você realizou o {session.workout_day_name}. O treino sugerido era {suggestedDay!.name}.
        </p>
      )}

      <div className="wdc-actions">
        <Link href="/history" className="wdc-btn-primary">
          Ver histórico →
        </Link>
        <Link href="/workout/today" className="wdc-btn-secondary">
          Fazer outro treino
        </Link>
      </div>

      <div className="ring-deco" aria-hidden />
    </div>
  );
}
