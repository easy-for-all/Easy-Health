"use client";

import "./workout-ui.css";

const WEEK_LABELS = ["S", "T", "Q", "Q", "S", "S", "D"];

type StreakCardProps = {
  streak: number;
  weeklySessions: number;
  weeklyGoal: number;
  todayIndex?: number; // 0 = Sunday…6 = Saturday (JS getDay)
};

export function StreakCard({ streak, weeklySessions, weeklyGoal, todayIndex }: StreakCardProps) {
  const today = todayIndex ?? new Date().getDay();
  // Map JS Sunday=0 to our Mon-first display (Mon=0…Sun=6)
  const todayDisplay = today === 0 ? 6 : today - 1;

  return (
    <div className="streak-card">
      <div className="sk-top">
        <div className="sk-flame">
          <div className="sk-fi">
            <span style={{ fontSize: 16, lineHeight: 1 }}>🔥</span>
          </div>
          <span>
            {streak > 0 ? `${streak} dia${streak === 1 ? "" : "s"} seguidos` : "Comece sua ofensiva"}
          </span>
        </div>
        <div className="sk-frac">
          {weeklySessions}
          <em>/{weeklyGoal} esta semana</em>
        </div>
      </div>

      <div className="sk-week">
        {WEEK_LABELS.map((label, i) => {
          const isDone = i < weeklySessions;
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
