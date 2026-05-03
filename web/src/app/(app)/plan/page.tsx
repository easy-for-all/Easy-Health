"use client";

import { useEffect, useRef, useState } from "react";
import { ApiError, api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutPlan } from "@/shared/types/workout";
import type { HealthProfile, ActivityType } from "@/shared/types/health-profile";

const ACTIVITY_LABELS: Record<ActivityType, string> = {
  musculacao: "Musculação",
  cardio:     "Cardio",
  natacao:    "Natação",
  corrida:    "Corrida",
  funcional:  "Funcional",
  caminhada:  "Caminhada",
  hiit:       "HIIT",
};

const ACTIVITY_ICONS: Record<ActivityType, string> = {
  musculacao: "🏋️",
  cardio:     "❤️",
  natacao:    "🏊",
  corrida:    "🏃",
  funcional:  "⚡",
  caminhada:  "🚶",
  hiit:       "🔥",
};

const ACTIVITY_LIST: ActivityType[] = [
  "musculacao", "cardio", "natacao", "corrida", "funcional", "caminhada", "hiit",
];

const GOAL_LABELS: Record<string, string> = {
  lose_weight: "Perder peso",
  gain_muscle: "Ganhar músculo",
  maintain:    "Manter peso",
  health:      "Saúde geral",
};

const LEVEL_LABELS: Record<string, string> = {
  beginner:     "Iniciante",
  intermediate: "Intermediário",
  advanced:     "Avançado",
};

const GENERATION_STEPS = [
  "Analisando seu perfil",
  "Considerando suas preferências",
  "Montando divisão semanal",
  "Criando os treinos",
  "Ajustando intensidade",
  "Finalizando planejamento",
];

type Phase =
  | "loading"
  | "view"
  | "wizard_profile"
  | "wizard_days"
  | "wizard_prefs"
  | "wizard_generating";

const WIZARD_PHASES: Phase[] = ["wizard_profile", "wizard_days", "wizard_prefs"];
const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function PlanPage() {
  const [phase, setPhase]               = useState<Phase>("loading");
  const [plan, setPlan]                 = useState<WorkoutPlan | null>(null);
  const [profile, setProfile]           = useState<HealthProfile | null>(null);
  const [daysPerWeek, setDaysPerWeek]   = useState(3);
  const [selectedPrefs, setSelectedPrefs] = useState<ActivityType[]>(["musculacao"]);
  const [genStep, setGenStep]           = useState(0);
  const [error, setError]               = useState("");
  const genStepRef                      = useRef(0);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
    ]).then(([p, hp]) => {
      setPlan(p);
      setProfile(hp);
      if (hp) {
        setDaysPerWeek(hp.training_days_per_week ?? 3);
        setSelectedPrefs(hp.activity_preferences?.length ? hp.activity_preferences : ["musculacao"]);
      }
      setPhase(p ? "view" : hp ? "wizard_profile" : "wizard_days");
    });
  }, []);

  function startWizard() {
    setError("");
    setPhase(profile ? "wizard_profile" : "wizard_days");
  }

  function togglePref(pref: ActivityType) {
    setSelectedPrefs((prev) =>
      prev.includes(pref) ? prev.filter((p) => p !== pref) : [...prev, pref]
    );
  }

  async function handleGenerate() {
    setPhase("wizard_generating");
    genStepRef.current = 0;
    setGenStep(0);
    setError("");

    const STEP_MS = 600;
    const interval = setInterval(() => {
      const next = Math.min(genStepRef.current + 1, GENERATION_STEPS.length - 1);
      genStepRef.current = next;
      setGenStep(next);
    }, STEP_MS);

    try {
      const [newPlan] = await Promise.all([
        api.post<WorkoutPlan>("/api/v1/workout_plan/regenerate", {
          training_days_per_week: daysPerWeek,
          activity_preferences:   selectedPrefs,
        }),
        new Promise<void>((resolve) =>
          setTimeout(resolve, GENERATION_STEPS.length * STEP_MS)
        ),
      ]);
      clearInterval(interval);
      setPlan(newPlan);
      setPhase("view");
    } catch (err) {
      clearInterval(interval);
      if (err instanceof ApiError && err.status === 401) {
        window.location.replace("/login");
        return;
      }
      setError(err instanceof Error ? err.message : "Erro ao gerar planejamento");
      setPhase("wizard_prefs");
    }
  }

  if (phase === "loading") return <LoadingScreen />;

  const wizardStep = WIZARD_PHASES.indexOf(phase);

  return (
    <div className="min-h-screen px-4 py-6">
      <header className="mb-6">
        <h1 className="text-xl font-bold text-gray-900">Planejamento de Treinos</h1>
      </header>

      {wizardStep >= 0 && phase !== "wizard_generating" && (
        <div className="mb-6 flex gap-1">
          {WIZARD_PHASES.map((_, i) => (
            <div
              key={i}
              className={`h-1 flex-1 rounded-full transition-colors ${
                i <= wizardStep ? "bg-primary-500" : "bg-gray-200"
              }`}
            />
          ))}
        </div>
      )}

      {phase === "view" && plan && (
        <>
          <PlanView plan={plan} />
          <button
            onClick={startWizard}
            className="mt-6 w-full rounded-xl border border-gray-200 py-3 text-sm font-medium text-gray-600 hover:bg-gray-50"
          >
            Replanejar
          </button>
        </>
      )}

      {phase === "wizard_profile" && profile && (
        <WizardProfile
          profile={profile}
          onNext={() => setPhase("wizard_days")}
          onCancel={plan ? () => setPhase("view") : undefined}
        />
      )}

      {phase === "wizard_days" && (
        <WizardDays
          selected={daysPerWeek}
          onSelect={setDaysPerWeek}
          onNext={() => setPhase("wizard_prefs")}
          onBack={() => setPhase(profile ? "wizard_profile" : "view")}
        />
      )}

      {phase === "wizard_prefs" && (
        <WizardPrefs
          selected={selectedPrefs}
          onToggle={togglePref}
          error={error}
          onConfirm={handleGenerate}
          onBack={() => setPhase("wizard_days")}
        />
      )}

      {phase === "wizard_generating" && <GeneratingView step={genStep} />}
    </div>
  );
}

function PlanView({ plan }: { plan: WorkoutPlan }) {
  return (
    <div className="space-y-3">
      {plan.days?.map((day, idx) => (
        <div key={day.id} className="rounded-xl border border-gray-100 bg-white p-4">
          <p className="text-xs font-semibold text-gray-400">
            Treino {LETTERS[idx] ?? day.position ?? idx + 1}
          </p>
          <p className="font-semibold text-gray-900">{day.name}</p>
          <p className="mt-0.5 text-xs text-gray-400">
            {day.exercise_count} exercícios
            {day.muscle_groups?.length ? ` · ${day.muscle_groups.join(", ")}` : ""}
          </p>
        </div>
      ))}
    </div>
  );
}

function WizardProfile({
  profile,
  onNext,
  onCancel,
}: {
  profile: HealthProfile;
  onNext: () => void;
  onCancel?: () => void;
}) {
  const prefsText = profile.activity_preferences?.length
    ? profile.activity_preferences.map((a) => ACTIVITY_LABELS[a]).join(" · ")
    : "—";

  return (
    <div>
      {onCancel && (
        <button onClick={onCancel} className="mb-4 text-sm text-gray-400 hover:text-gray-600">
          ← Cancelar
        </button>
      )}
      <h2 className="mb-2 text-lg font-bold text-gray-900">Seu perfil de treino</h2>
      <p className="mb-4 text-sm text-gray-500">
        Vamos usar esses dados para montar seu planejamento.
      </p>

      <div className="rounded-2xl border border-gray-100 bg-white p-5 space-y-3">
        <ProfileSummaryRow label="Nível"      value={LEVEL_LABELS[profile.fitness_level]} />
        <ProfileSummaryRow label="Objetivo"   value={GOAL_LABELS[profile.goal]} />
        <ProfileSummaryRow label="Atividades" value={prefsText} />
      </div>

      <button
        onClick={onNext}
        className="mt-6 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600"
      >
        Continuar →
      </button>
    </div>
  );
}

function ProfileSummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-sm text-gray-500">{label}</span>
      <span className="text-sm font-medium text-gray-900">{value}</span>
    </div>
  );
}

function WizardDays({
  selected,
  onSelect,
  onNext,
  onBack,
}: {
  selected: number;
  onSelect: (n: number) => void;
  onNext: () => void;
  onBack: () => void;
}) {
  return (
    <div>
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
        ← Voltar
      </button>
      <h2 className="mb-2 text-lg font-bold text-gray-900">Quantos dias por semana?</h2>
      <p className="mb-6 text-sm text-gray-500">Escolha com base na sua disponibilidade.</p>

      <div className="flex justify-center gap-3">
        {[2, 3, 4, 5, 6].map((n) => (
          <button
            key={n}
            onClick={() => onSelect(n)}
            className={`flex h-14 w-14 items-center justify-center rounded-full text-lg font-bold transition ${
              selected === n
                ? "bg-primary-500 text-white shadow-md"
                : "border-2 border-gray-200 text-gray-600 hover:border-primary-300"
            }`}
          >
            {n}
          </button>
        ))}
      </div>
      <p className="mt-3 text-center text-xs text-gray-400">dias por semana</p>

      <button
        onClick={onNext}
        className="mt-8 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600"
      >
        Continuar →
      </button>
    </div>
  );
}

function WizardPrefs({
  selected,
  onToggle,
  error,
  onConfirm,
  onBack,
}: {
  selected: ActivityType[];
  onToggle: (v: ActivityType) => void;
  error: string;
  onConfirm: () => void;
  onBack: () => void;
}) {
  return (
    <div>
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
        ← Voltar
      </button>
      <h2 className="mb-2 text-lg font-bold text-gray-900">Tipos de atividade</h2>
      <p className="mb-4 text-sm text-gray-500">
        Revise e ajuste conforme preferir para este planejamento.
      </p>

      {error && (
        <p className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
      )}

      <div className="grid grid-cols-2 gap-3">
        {ACTIVITY_LIST.map((act) => {
          const isSelected = selected.includes(act);
          return (
            <button
              key={act}
              onClick={() => onToggle(act)}
              className={`flex items-center gap-3 rounded-xl border-2 p-4 text-left transition ${
                isSelected
                  ? "border-primary-500 bg-primary-50"
                  : "border-gray-200 hover:border-gray-300"
              }`}
            >
              <span className="text-xl leading-none">{ACTIVITY_ICONS[act]}</span>
              <span className="text-sm font-medium text-gray-900">{ACTIVITY_LABELS[act]}</span>
            </button>
          );
        })}
      </div>

      <button
        onClick={onConfirm}
        disabled={selected.length === 0}
        className="mt-6 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-50 hover:bg-primary-600"
      >
        Criar treino
      </button>
    </div>
  );
}

function GeneratingView({ step }: { step: number }) {
  return (
    <div className="flex flex-col items-center py-12">
      <div className="mb-10 h-12 w-12 animate-spin rounded-full border-4 border-primary-500 border-t-transparent" />
      <div className="w-full space-y-4">
        {GENERATION_STEPS.map((msg, idx) => (
          <div
            key={idx}
            className={`flex items-center gap-3 transition-all duration-500 ${
              idx <= step ? "opacity-100 translate-x-0" : "opacity-20"
            }`}
          >
            <div
              className={`h-2 w-2 flex-shrink-0 rounded-full transition-colors ${
                idx < step
                  ? "bg-primary-500"
                  : idx === step
                  ? "animate-pulse bg-primary-400"
                  : "bg-gray-200"
              }`}
            />
            <p
              className={`text-sm font-medium ${
                idx < step ? "text-primary-700" : idx === step ? "text-gray-800" : "text-gray-400"
              }`}
            >
              {msg}
              {idx < step && " ✓"}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
