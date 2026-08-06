"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { LoadingScreen } from "@/shared/components/loading-screen";
import { AgentOrb } from "@/shared/components/agent-orb";
import { ConfettiBurst, GlowPulse } from "@/shared/components/motion";
import { muscleLabel } from "@/shared/utils/muscle-labels";
import { trackEvent } from "@/shared/lib/analytics";
import {
  fetchAnonymousPlan,
  fetchAnonymousToday,
  fetchAnonymousState,
  type AnonymousPlan,
  type AnonymousState,
} from "@/features/anonymous/anonymous-plan";
import type { WorkoutDay } from "@/shared/types/workout";
import "@/shared/components/workout/workout-ui.css";

// O espelho anônimo de /workouts/ready.
//
// Página nova e não um fork daquela: /workouts/ready vive sob (app), passa por
// UpgradeGate e busca endpoints autenticados. O que ela mostra a mais —
// AITrainerBubble, ProgressiveProfilingSheet, PrePermissionCard, PushFeedback —
// depende de conta e renderizaria vazio aqui.
export default function AnonymousPlanReadyPage() {
  const router = useRouter();
  const [plan, setPlan] = useState<AnonymousPlan | null>(null);
  const [day, setDay] = useState<WorkoutDay | null>(null);
  const [state, setState] = useState<AnonymousState | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;

    (async () => {
      const [loadedPlan, today, loadedState] = await Promise.all([
        fetchAnonymousPlan().catch(() => null),
        fetchAnonymousToday().catch(() => ({ day: null })),
        fetchAnonymousState().catch(() => null),
      ]);
      if (!active) return;

      setPlan(loadedPlan);
      setState(loadedState);
      setDay(today?.day ?? null);
      setFailed(loadedPlan === null);
      setLoading(false);

      if (loadedPlan) {
        trackEvent("workout_viewed", { source: "anonymous_ready", workout_plan_id: loadedPlan.id });
      }
    })();

    return () => {
      active = false;
    };
  }, []);

  const exercises = useMemo(() => day?.exercises ?? [], [day]);
  const muscleGroups = useMemo(() => {
    const groups = new Set<string>();
    exercises.forEach((exercise) => exercise.muscle_group && groups.add(exercise.muscle_group));
    return Array.from(groups);
  }, [exercises]);

  function handleStart() {
    trackEvent("workout_start_clicked", { source: "anonymous_ready", workout_day_id: day?.id ?? undefined });
    router.push(day?.id ? `/plano/treino?day=${day.id}` : "/plano/treino");
  }

  if (loading) return <LoadingScreen />;

  // Sem plano não há o que mostrar, e insistir numa tela vazia esconderia o
  // problema. O cadastro é a saída que sempre funciona.
  if (failed || !plan) {
    return (
      <div style={{ padding: "72px 20px" }}>
        <h1 className="wizard-title">Não conseguimos abrir seu treino</h1>
        <p className="wizard-sub">Crie sua conta para não perder o que você respondeu.</p>
        <button className="wizard-cta" onClick={() => router.push("/sign-up?from=anonymous_recovery")}>
          Criar minha conta
        </button>
      </div>
    );
  }

  const dayName = day?.custom_name || day?.name || "Seu treino";
  const remaining = state?.plans_remaining ?? 0;

  return (
    <div style={{ padding: "52px 20px 40px" }}>
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
          Pode começar agora. A conta fica para depois.
        </p>
      </div>

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
          {exercises.length} exercícios
        </p>
        {muscleGroups.length > 0 && (
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {muscleGroups.slice(0, 4).map((group) => (
              <span key={group} className="tag-chip muscle">{muscleLabel(group)}</span>
            ))}
          </div>
        )}
      </div>

      {plan.ai_rationale && (
        <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--r-lg)", padding: 16, marginBottom: 14 }}>
          <p style={{ fontSize: 13, color: "var(--text-muted)", margin: 0, lineHeight: 1.55 }}>{plan.ai_rationale}</p>
        </div>
      )}

      <button className="wizard-cta" onClick={handleStart} disabled={!day}>
        Começar treino
      </button>

      {/* O CTA de conta é honesto sobre o que ela resolve: o treino já existe, o
          que a conta faz é impedir que ele desapareça com o aparelho. */}
      <div style={{ marginTop: 24, textAlign: "center" }}>
        <p style={{ fontSize: 13, color: "var(--text-muted)", margin: "0 0 8px" }}>
          Seu treino está salvo só neste aparelho.
        </p>
        <button
          onClick={() => router.push("/sign-up?from=anonymous_save")}
          style={{ background: "transparent", border: 0, color: "var(--primary)", fontWeight: 700, fontSize: 14, cursor: "pointer" }}
        >
          Criar conta e guardar meu progresso
        </button>
        {remaining < 3 && (
          <p style={{ fontSize: 12, color: "var(--text-muted)", marginTop: 10 }}>
            {remaining > 0
              ? `Você pode gerar mais ${remaining} ${remaining === 1 ? "treino" : "treinos"} sem conta.`
              : "Para gerar outro treino, crie sua conta."}
          </p>
        )}
      </div>
    </div>
  );
}
