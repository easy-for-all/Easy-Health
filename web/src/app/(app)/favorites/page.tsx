"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { WorkoutRow } from "@/shared/components/workout/workout-row";
import { ExerciseRow } from "@/shared/components/workout/exercise-row";
import "@/shared/components/workout/workout-ui.css";
import type { WorkoutPlan, WorkoutDay } from "@/shared/types/workout";

type QuickModality = "musculacao" | "funcional" | "hiit" | "cardio";

const QUICK_MODALITIES: { id: QuickModality; label: string; emoji: string }[] = [
  { id: "musculacao", label: "Musculação", emoji: "🏋️" },
  { id: "funcional", label: "Funcional", emoji: "⚡" },
  { id: "hiit", label: "HIIT", emoji: "🔥" },
  { id: "cardio", label: "Cardio", emoji: "🏃" },
];

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
  const [modalOpen, setModalOpen] = useState(false);
  const [generatingQuick, setGeneratingQuick] = useState(false);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<FavoriteExercise[]>("/api/v1/exercises/favorites").catch(() => []),
    ]).then(([p, exs]) => {
      setPlan(p);
      setExercises(Array.isArray(exs) ? exs : []);
    }).finally(() => setLoading(false));
  }, []);

  async function handleQuickWorkout(modality: QuickModality) {
    setGeneratingQuick(true);
    setModalOpen(false);
    try {
      await api.post("/api/v1/quick_workouts", { modality, duration_minutes: 45 });
      router.push("/workout/today?quick=true");
    } catch {
      setGeneratingQuick(false);
    }
  }

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

      {/* CTA card — quick workout with favorites */}
      <div style={{
        background: "var(--surface)", border: "1px solid var(--border)",
        borderRadius: "var(--r-lg)", padding: "18px", marginBottom: 24,
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 12 }}>
          <div style={{
            width: 40, height: 40, borderRadius: "var(--r-md)", flexShrink: 0,
            background: "var(--primary-soft)", display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 20,
          }}>
            ❤️
          </div>
          <div>
            <p style={{ fontWeight: 700, fontSize: 14, margin: 0 }}>Favoritos alimentam a IA</p>
            <p style={{ fontSize: 12, color: "var(--text-dim)", margin: "2px 0 0" }}>
              Treinos e exercícios marcados têm prioridade no plano e no treino rápido.
            </p>
          </div>
        </div>
        <button
          onClick={() => exercises.length > 0 && setModalOpen(true)}
          disabled={exercises.length === 0 || generatingQuick}
          title={exercises.length === 0 ? "Adicione exercícios favoritos primeiro" : undefined}
          style={{
            width: "100%", padding: "13px", borderRadius: "var(--r-md)", border: "none",
            background: exercises.length > 0
              ? "linear-gradient(180deg, var(--primary), var(--primary-2))"
              : "var(--border)",
            color: exercises.length > 0 ? "var(--on-primary)" : "var(--text-dim)",
            fontWeight: 700, fontSize: 14, cursor: exercises.length > 0 ? "pointer" : "not-allowed",
            opacity: generatingQuick ? 0.7 : 1,
            transition: "opacity 0.2s",
          }}
        >
          {generatingQuick ? "Gerando treino…" : "⚡ Criar Treino Rápido com Favoritos"}
        </button>
        {exercises.length === 0 && (
          <p style={{ fontSize: 11, color: "var(--text-dim)", textAlign: "center", marginTop: 8 }}>
            Adicione exercícios favoritos durante o treino para liberar esta função.
          </p>
        )}
      </div>

      {/* Modality selector modal */}
      <AnimatePresence>
        {modalOpen && (
          <div
            style={{ position: "fixed", inset: 0, zIndex: 50, background: "rgba(0,0,0,.6)", backdropFilter: "blur(4px)" }}
            onClick={() => setModalOpen(false)}
          >
            <motion.div
              style={{
                position: "absolute", bottom: 0, left: 0, right: 0,
                background: "var(--bg-2)", borderRadius: "var(--r-xl) var(--r-xl) 0 0",
                padding: "20px 20px max(48px, var(--safe-area-bottom))",
              }}
              onClick={(e) => e.stopPropagation()}
              initial={{ y: "100%" }}
              animate={{ y: 0 }}
              exit={{ y: "100%" }}
              transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
            >
              <div style={{ display: "flex", justifyContent: "center", marginBottom: 16 }}>
                <div style={{ width: 36, height: 4, borderRadius: 9, background: "var(--border-strong)" }} />
              </div>
              <h2 style={{ fontFamily: "var(--font-display)", fontSize: 18, fontWeight: 700, margin: "0 0 6px" }}>
                Escolha a modalidade
              </h2>
              <p style={{ fontSize: 13, color: "var(--text-dim)", margin: "0 0 20px" }}>
                Seus exercícios favoritos serão priorizados na montagem.
              </p>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                {QUICK_MODALITIES.map((m) => (
                  <button
                    key={m.id}
                    onClick={() => handleQuickWorkout(m.id)}
                    style={{
                      padding: "16px 12px", borderRadius: "var(--r-md)",
                      background: "var(--surface)", border: "1px solid var(--border)",
                      display: "flex", flexDirection: "column", alignItems: "center", gap: 6,
                      cursor: "pointer",
                    }}
                  >
                    <span style={{ fontSize: 28 }}>{m.emoji}</span>
                    <span style={{ fontSize: 14, fontWeight: 600, color: "var(--text)" }}>{m.label}</span>
                  </button>
                ))}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

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
                  onFavorite={() => day.id != null && toggleFavorite(day.id)}
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
                  onFavorite={() => day.id != null && toggleFavorite(day.id)}
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
