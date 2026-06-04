"use client";

import Link from "next/link";
import "./workout-ui.css";

type HeroWorkoutProps = {
  dayLabel: string;
  workoutName: string;
  workoutSub?: string;
  exerciseCount?: number;
  estimatedMin?: number;
  href?: string;
  onClick?: () => void;
};

export function HeroWorkout({
  dayLabel,
  workoutName,
  workoutSub,
  exerciseCount,
  estimatedMin,
  href = "/workout/today",
  onClick,
}: HeroWorkoutProps) {
  const inner = (
    <div className="hero-workout">
      <div className="hw-top">
        <span className="hw-day">{dayLabel}</span>
        <span className="hw-ready">✓ Pronto pra treinar</span>
      </div>
      <h2>{workoutName}</h2>
      {workoutSub && <p className="hw-sub">{workoutSub}</p>}
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
