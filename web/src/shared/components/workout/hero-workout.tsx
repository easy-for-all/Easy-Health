"use client";

import Link from "next/link";
import "./workout-ui.css";

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
  forearms: "Antebraços", calves: "Panturrilhas", glutes: "Glúteos", trapezius: "Trapézio",
};

type HeroWorkoutProps = {
  dayLabel: string;
  workoutName: string;
  workoutSub?: string;
  muscleGroups?: string[];
  exerciseCount?: number;
  estimatedMin?: number;
  href?: string;
  onClick?: () => void;
};

export function HeroWorkout({
  dayLabel,
  workoutName,
  workoutSub,
  muscleGroups,
  exerciseCount,
  estimatedMin,
  href = "/workout/today",
  onClick,
}: HeroWorkoutProps) {
  const uniqueMuscles = muscleGroups ? [...new Set(muscleGroups.filter(Boolean))] : [];

  const inner = (
    <div className="hero-workout">
      <div className="hw-top">
        <span className="hw-day">{dayLabel}</span>
        <span className="hw-ready">✓ Pronto pra treinar</span>
      </div>
      <h2>{workoutName}</h2>
      {workoutSub && <p className="hw-sub">{workoutSub}</p>}
      {uniqueMuscles.length > 0 ? (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 5, margin: "8px 0 4px" }}>
          {uniqueMuscles.slice(0, 4).map((m) => (
            <span key={m} className="tag-chip muscle">{MUSCLE_LABELS[m] ?? m}</span>
          ))}
        </div>
      ) : (
        <p style={{ fontSize: 12, color: "oklch(1 0 0 / 0.45)", margin: "4px 0" }}>Grupamentos não definidos</p>
      )}
      {(exerciseCount !== undefined || estimatedMin !== undefined) && (
        <div className="hw-meta">
          {exerciseCount !== undefined && (
            <div className="m">
              <b>{exerciseCount}</b>
              <span>exercícios</span>
            </div>
          )}
          {estimatedMin !== undefined && (
            <div className="m">
              <b>{estimatedMin}</b>
              <span>min estimado</span>
            </div>
          )}
        </div>
      )}
      <span className="hw-cta">
        Treinar agora
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" style={{ width: 16, height: 16 }}>
          <path d="M5 12h14M12 5l7 7-7 7" />
        </svg>
      </span>
      <div className="ring-deco" aria-hidden />
    </div>
  );

  if (onClick) {
    return (
      <button onClick={onClick} style={{ display: "block", width: "100%", background: "none", border: 0, padding: 0, cursor: "pointer" }}>
        {inner}
      </button>
    );
  }

  return <Link href={href} style={{ display: "block", textDecoration: "none" }}>{inner}</Link>;
}
