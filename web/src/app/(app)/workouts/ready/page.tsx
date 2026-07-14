"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { UpgradeGate } from "@/shared/components/upgrade-gate";
import { trackOnboardingEvent } from "@/shared/lib/onboarding-tracking";
import { AgentOrb } from "@/shared/components/agent-orb";
import { AITrainerBubble } from "@/shared/components/ai-trainer";
import { ConfettiBurst, GlowPulse } from "@/shared/components/motion";
import { WorkoutRow } from "@/shared/components/workout/workout-row";
import { ExerciseInfoModal } from "@/shared/components/workout/exercise-info-modal";
import { ProgressiveProfilingSheet } from "@/features/workout/progressive-profiling-sheet";
import { PrePermissionCard } from "@/features/notifications/pre-permission-card";
import { AppPromoCard } from "@/features/app-promo/app-promo-card";
import { PushFeedbackLink } from "@/features/notifications/push-feedback-link";
import { muscleLabel } from "@/shared/utils/muscle-labels";
import "@/shared/components/workout/workout-ui.css";
import type { WorkoutPlan, WorkoutDay, WorkoutDayExercise } from "@/shared/types/workout";

const PREVIEW_LIMIT = 6;

export default function WorkoutReadyPage() {
  return (
    <UpgradeGate>
      <WorkoutReadyContent />
    </UpgradeGate>
  );
}

function WorkoutReadyContent() {
  const router = useRouter();
  const [plan, setPlan] = useState<WorkoutPlan | null>(null);
  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [loading, setLoading] = useState(true);
  const [previewExpanded, setPreviewExpanded] = useState(false);
  const [rationaleExpanded, setRationaleExpanded] = useState(false);
  const [activeExercise, setActiveExercise] = useState<WorkoutDayExercise | null>(null);
  const [showProfiling, setShowProfiling] = useState(false);
  const previewTracked = useRef(false);

  useEffect(() => {
    async function load() {
      const [p, today] = await Promise.all([
        api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
        api.get<{ day: WorkoutDay | null }>("/api/v1/workout_plan/today").catch(() => ({ day: null })),
      ]);
      setPlan(p);

      let resolvedDay = today?.day ?? null;
      // Rest day today, or plan has no "today" mapping — fall back to the
      // plan's first day, fetched with full exercise detail.
      if (!resolvedDay && p?.days?.length && p.days[0].id !== null) {
        resolvedDay = await api
          .get<{ day: WorkoutDay }>(`/api/v1/workout_days/${p.days[0].id}`)
          .then((r) => r.day)
          .catch(() => null);
      }
      setDay(resolvedDay);
      setLoading(false);

      trackOnboardingEvent("activation_ready_screen_viewed", {
        metadata: { workout_plan_id: p?.id ?? null, workout_day_id: resolvedDay?.id ?? null },
      });
    }
    load();
  }, []);

  const exercises = useMemo(() => day?.exercises ?? [], [day]);
  const previewExercises = exercises.slice(0, PREVIEW_LIMIT);
  const muscleGroups = useMemo(() => {
    const set = new Set<string>();
    exercises.forEach((ex) => ex.muscle_group && set.add(ex.muscle_group));
    return Array.from(set);
  }, [exercises]);

  function handleTogglePreview() {
    setPreviewExpanded((v) => !v);
    if (!previewTracked.current) {
      previewTracked.current = true;
      trackOnboardingEvent("activation_preview_viewed", {
        metadata: { workout_plan_id: plan?.id ?? null, action: "expand_preview" },
      });
    }
  }

  function handleOpenExercise(ex: WorkoutDayExercise) {
    setActiveExercise(ex);
    trackOnboardingEvent("activation_exercise_details_opened", {
      metadata: { workout_plan_id: plan?.id ?? null, exercise_id: ex.exercise_id, exercise_name: ex.name },
    });
  }

  function handleStart() {
    trackOnboardingEvent("activation_start_clicked", {
      metadata: { workout_plan_id: plan?.id ?? null, workout_day_id: day?.id ?? null },
    });
    router.push(day?.id ? `/workout/today?day=${day.id}` : "/workout/today");
  }

  function handleViewFull() {
    trackOnboardingEvent("activation_preview_viewed", {
      metadata: { workout_plan_id: plan?.id ?? null, action: "view_full_workout" },
    });
    router.push("/workouts");
  }

  if (loading) return <LoadingScreen />;

  const dayName = day?.custom_name || day?.name || "Seu treino";
  const rationale = plan?.ai_rationale || plan?.user_explanation;

  return (
    <div style={{ minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 100px" }}>
      <ConfettiBurst preset="workout" />

      <div style={{ textAlign: "center", marginBottom: 24 }}>
        <div style={{ display: "inline-block" }}>
          <GlowPulse color="green" radius={999}>
            <AgentOrb size="header" glyph pulse />
          </GlowPulse>
        </div>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: 24, fontWeight: 700, margin: "16px 0 6px", letterSpacing: "-0.02em" }}>
          Seu treino ficou pronto 💪
        </h1>
        <p style={{ fontSize: 14, color: "var(--text-muted)", margin: 0 }}>
          Criamos um plano inicial para você começar hoje.
        </p>
      </div>

      {/* Card resumo */}
      <div
        style={{
          background: "var(--primary-soft)",
          border: "1px solid oklch(0.685 var(--accent-c, 0.17) var(--accent-h, 258) / .3)",
          borderRadius: "var(--r-lg)",
          padding: 18,
          marginBottom: 14,
        }}
      >
        <p className="eyebrow" style={{ color: "var(--primary)", marginBottom: 6 }}>Treino de hoje</p>
        <p style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: "0 0 4px", letterSpacing: "-0.015em" }}>
          {dayName}
        </p>
        <p style={{ fontSize: 13, color: "var(--text-muted)", margin: "0 0 10px" }}>
          {exercises.length} exercícios{plan?.strategy?.training_split ? ` · ${plan.strategy.training_split}` : ""}
        </p>
        {muscleGroups.length > 0 && (
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {muscleGroups.slice(0, 4).map((m) => (
              <span key={m} className="tag-chip muscle">{muscleLabel(m)}</span>
            ))}
          </div>
        )}
      </div>

      {/* Preview accordion */}
      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", marginBottom: 14, overflow: "hidden" }}>
        <button
          onClick={handleTogglePreview}
          style={{ width: "100%", display: "flex", alignItems: "center", justifyContent: "space-between", padding: "14px 16px", background: "transparent", border: 0, cursor: "pointer", color: "var(--text)" }}
        >
          <span style={{ fontWeight: 700, fontSize: 14 }}>Ver exercícios</span>
          <span style={{ fontSize: 13, color: "var(--text-muted)" }}>{previewExpanded ? "▲" : "▼"}</span>
        </button>
        {previewExpanded && (
          <div style={{ padding: "0 12px 12px", display: "flex", flexDirection: "column", gap: 8 }}>
            {previewExercises.length === 0 ? (
              <p style={{ fontSize: 13, color: "var(--text-muted)", padding: "0 4px 8px" }}>
                Detalhes do treino disponíveis assim que você iniciar.
              </p>
            ) : (
              previewExercises.map((ex, idx) => (
                <WorkoutRow
                  key={ex.workout_day_exercise_id}
                  badge={String(idx + 1)}
                  name={ex.name}
                  sub={ex.duration_minutes ? `${ex.duration_minutes} min` : `${ex.sets}x${ex.reps}`}
                  tags={ex.muscle_group ? [muscleLabel(ex.muscle_group)] : []}
                  onClick={() => handleOpenExercise(ex)}
                />
              ))
            )}
            {exercises.length > previewExercises.length && (
              <p style={{ fontSize: 12, color: "var(--text-muted)", textAlign: "center", margin: "4px 0 0" }}>
                +{exercises.length - previewExercises.length} exercícios no treino completo
              </p>
            )}
          </div>
        )}
      </div>

      {/* Por que esse plano? */}
      {rationale && (
        <div style={{ marginBottom: 20 }}>
          <button
            onClick={() => setRationaleExpanded((v) => !v)}
            style={{ display: "flex", alignItems: "center", gap: 6, background: "transparent", border: 0, cursor: "pointer", color: "var(--primary)", fontSize: 13, fontWeight: 700, padding: 0 }}
          >
            Por que esse plano? {rationaleExpanded ? "▲" : "▼"}
          </button>
          {rationaleExpanded && (
            <div style={{ marginTop: 10 }}>
              <AITrainerBubble message={rationale} mood="speaking" />
            </div>
          )}
        </div>
      )}

      {/* Contextual push opt-in (native only, after the workout is ready) */}
      <PrePermissionCard onboardingStage="workout_ready" />

      {/* App promo (web only — mirror of PrePermissionCard, hidden in the native app) */}
      <AppPromoCard placement="ready" />

      {/* CTAs */}
      <button
        onClick={handleStart}
        style={{
          width: "100%", borderRadius: "var(--r-pill)", padding: "16px",
          background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
          color: "var(--on-primary)", fontWeight: 700, fontSize: 15, border: 0,
          cursor: "pointer", boxShadow: "var(--glow)", marginBottom: 10,
        }}
      >
        ▶ Fazer meu primeiro treino
      </button>
      <button
        onClick={handleViewFull}
        style={{
          width: "100%", borderRadius: "var(--r-pill)", padding: "14px",
          background: "var(--surface)", color: "var(--text)", fontWeight: 700, fontSize: 14,
          border: "1px solid var(--border)", cursor: "pointer",
        }}
      >
        👀 Ver treino completo
      </button>

      {!showProfiling && (
        <button
          onClick={() => setShowProfiling(true)}
          style={{
            display: "block", width: "100%", textAlign: "center", marginTop: 16,
            background: "transparent", border: 0, cursor: "pointer",
            color: "var(--text-muted)", fontSize: 12.5,
          }}
        >
          Quer deixar esse treino mais certeiro? Responder 1 pergunta
        </button>
      )}

      <PushFeedbackLink />

      <ExerciseInfoModal exercise={activeExercise} onClose={() => setActiveExercise(null)} />
      <ProgressiveProfilingSheet
        open={showProfiling}
        trigger="ready_screen"
        onClose={() => setShowProfiling(false)}
      />
    </div>
  );
}
