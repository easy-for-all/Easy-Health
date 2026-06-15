"use client";

import "./workout-ui.css";

const WEEK_LABELS = ["D", "S", "T", "Q", "Q", "S", "S"];

type StreakCardProps = {
  streak: number;
  weeklySessions: number;
  weeklyGoal: number;
  todayIndex?: number; // 0 = Sunday…6 = Saturday (JS getDay) — Sun-first
  completedDayIndices?: number[]; // Sun=0..Sat=6, actual days completed this week
};

export function StreakCard({ streak, weeklySessions, weeklyGoal, todayIndex, completedDayIndices }: StreakCardProps) {
  // JS getDay(): 0=Sun, 1=Mon, ..., 6=Sat — matches our Sun-first labels directly
  const todayDisplay = todayIndex ?? new Date().getDay();

  return (
    <div className="streak-card">
      {/* Streak global — dias consecutivos */}
      <div className="sk-top">
        <div className="sk-flame">
          <div className="sk-fi">
            <span style={{ fontSize: 16, lineHeight: 1 }}>🔥</span>
          </div>
          <div>
            <span>
              {streak > 0 ? `${streak} dia${streak === 1 ? "" : "s"} seguidos` : "Comece sua ofensiva"}
            </span>
            <p className="sk-streak-label">sequência global</p>
          </div>
        </div>

        {/* Treinos da semana — conceito separado */}
        <div className="sk-weekly-block">
          <div className="sk-frac">
            {weeklySessions}
            <em>/{weeklyGoal}</em>
          </div>
          <p className="sk-weekly-label">esta semana</p>
        </div>
      </div>

      {/* Divisor visual */}
      <div className="sk-divider" />

      {/* Pontos da semana atual */}
      <div className="sk-week">
        {WEEK_LABELS.map((label, i) => {
          const isFuture = i > todayDisplay;
          const isDone = isFuture
            ? false
            : (completedDayIndices ?? []).includes(i);
          const isToday = i === todayDisplay;
          const dotClass = ["sk-dot", isDone ? "done" : "", isToday && !isDone ? "today" : ""].filter(Boolean).join(" ");
          return (
            <div key={i} className="sk-day">
              <div className={dotClass}>
                {isDone && (
                  <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" style={{ width: 13, height: 13 }}>
                    <path d="M20 6L9 17l-5-5" />
                  </svg>
                )}
              </div>
              <small>{label}</small>
            </div>
          );
        })}
      </div>
    </div>
  );
}
