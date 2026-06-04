"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { WorkoutRow } from "@/shared/components/workout/workout-row";
import { ExerciseRow } from "@/shared/components/workout/exercise-row";
import "@/shared/components/workout/workout-ui.css";
import type { WorkoutPlan, WorkoutDay } from "@/shared/types/workout";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

type FavoriteExercise = {
  id: number;
  name: string;
  muscle_group: string | null;
  image_url: string;
};

export default function FavoritesPage() {
  const router = useRouter();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [exercises, setExercises] = useState<FavoriteExercise[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<FavoriteExercise[]>("/api/v1/exercises/favorites").catch(() => []),
    ]).then(([p, exs]) => {
      setPlan(p);
      setExercises(exs ?? []);
    }).finally(() => setLoading(false));
  }, []);

  async function toggleFavorite(dayId: number) {
    if (!plan) return;
    const prev = plan.days.find((d) => d.id === dayId)?.favorited ?? false;
    setPlan((p) => p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, favorited: !prev } : d) } : p);
    await api.patch(`/api/v1/workout_days/${dayId}/toggle_favorite`, {}).catch(() => {
      setPlan((p) => p ? { ...p, days: p.days.map((d) => d.id === dayId ? { ...d, favorited: prev } : d) } : p);
    });
  }

  if (loading) return <LoadingScreen />;

  const favDays = (plan?.days ?? []).filter((d) => d.favorited);
  const allDays = plan?.days ?? [];

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      {/* Header */}
      <header style={{ marginBottom: 20 }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 26, fontWeight: 700, letterSpacing: "-0.02em", margin: 0 }}>
          Favoritos
        </h1>
      </header>

      {/* Hero card */}
      <div className="fav-hero" style={{ marginBottom: 24 }}>
        <div className="fh">
          <div className="fhi">
            <svg viewBox="0 0 24 24">
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
          </div>
          <div className="fht">
            <b>Favoritos alimentam a IA</b>
            <p>Treinos e exercícios marcados aparecem com prioridade no seu plano gerado pela IA.</p>
          </div>
        </div>
        <p className="fp">
          Quanto mais você favorita, <b>mais personalizado</b> fica o seu planejamento. A IA considera
          seus favoritos ao sugerir séries, cargas e substituições.
        </p>
      </div>

      {/* Favorited workout days */}
      <section style={{ marginBottom: 28 }}>
        <p className="eyebrow" style={{ marginBottom: 10 }}>
          Treinos favoritos
          {favDays.length > 0 && <span style={{ marginLeft: 8, color: "var(--primary)" }}>{favDays.length}</span>}
        </p>

        {favDays.length === 0 ? (
          <EmptyState
            icon="🏋️"
            text="Nenhum treino favorito ainda."
            hint="Toque no ♡ em qualquer treino para adicioná-lo aqui."
          />
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {favDays.map((day: WorkoutDay) => {
              const idx = allDays.findIndex((d) => d.id === day.id);
              return (
                <WorkoutRow
                  key={day.id}
                  badge={LETTERS[idx] ?? String(idx + 1)}
                  name={day.name}
                  sub={day.exercise_count ? `${day.exercise_count} exercícios` : undefined}
                  tags={day.muscle_groups?.slice(0, 2)}
                  favorited
                  onFavorite={() => toggleFavorite(day.id)}
                  onClick={() => router.push(`/workout/today?day=${day.id}`)}
                />
              );
            })}
          </div>
        )}
      </section>

      {/* Favorited exercises */}
      <section>
        <p className="eyebrow" style={{ marginBottom: 10 }}>
          Exercícios favoritos
          {exercises.length > 0 && <span style={{ marginLeft: 8, color: "var(--primary)" }}>{exercises.length}</span>}
        </p>

        {exercises.length === 0 ? (
          <EmptyState
            icon="💪"
            text="Nenhum exercício favorito ainda."
            hint="Durante o treino, toque no ♡ ao lado de um exercício."
          />
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {exercises.map((ex) => (
              <ExerciseRow
                key={ex.id}
                name={ex.name}
                sub={ex.muscle_group ?? undefined}
                imageUrl={ex.image_url}
              />
            ))}
          </div>
        )}
      </section>

      {/* All plan days (to allow favoriting) */}
      {plan && allDays.filter((d) => !d.favorited).length > 0 && (
        <section style={{ marginTop: 28 }}>
          <p className="eyebrow" style={{ marginBottom: 10 }}>Adicionar favoritos</p>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {allDays.filter((d) => !d.favorited).map((day: WorkoutDay) => {
              const idx = allDays.findIndex((d) => d.id === day.id);
              return (
                <WorkoutRow
                  key={day.id}
                  badge={LETTERS[idx] ?? String(idx + 1)}
                  name={day.name}
                  sub={day.exercise_count ? `${day.exercise_count} exercícios` : undefined}
                  tags={day.muscle_groups?.slice(0, 2)}
                  favorited={false}
                  onFavorite={() => toggleFavorite(day.id)}
                  onClick={() => router.push(`/workout/today?day=${day.id}`)}
                />
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}

function EmptyState({ icon, text, hint }: { icon: string; text: string; hint: string }) {
  return (
    <div style={{ background: "var(--surface)", border: "1px dashed var(--border)", borderRadius: "var(--r-lg)", padding: "24px", textAlign: "center" }}>
      <p style={{ fontSize: 28, margin: "0 0 8px" }}>{icon}</p>
      <p style={{ fontWeight: 600, margin: "0 0 4px" }}>{text}</p>
      <p style={{ fontSize: 13, color: "var(--text-muted)", margin: 0 }}>{hint}</p>
    </div>
  );
}
