"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import type { Goal, FitnessLevel, ActivityType, Gender } from "@/shared/types/health-profile";

type TrainingLocation = "gym" | "home" | "outdoor" | "any";

interface FormData {
  goal: Goal | "";
  fitness_level: FitnessLevel | "";
  age: string;
  weight_kg: string;
  height_cm: string;
  gender: Gender | "";
  activity_preferences: ActivityType[];
  training_location: TrainingLocation | "";
}

const GOALS: { value: Goal; label: string; desc: string }[] = [
  { value: "lose_weight", label: "Perder peso",    desc: "Reduzir gordura corporal" },
  { value: "gain_muscle", label: "Ganhar músculo", desc: "Aumentar massa muscular" },
  { value: "maintain",    label: "Manter",         desc: "Manter o peso atual" },
  { value: "health",      label: "Saúde geral",    desc: "Melhorar qualidade de vida" },
];

const LEVELS: { value: FitnessLevel; label: string; desc: string }[] = [
  { value: "beginner",     label: "Iniciante",     desc: "Menos de 6 meses de treino" },
  { value: "intermediate", label: "Intermediário", desc: "6 meses a 2 anos" },
  { value: "advanced",     label: "Avançado",      desc: "Mais de 2 anos de treino" },
];

const ACTIVITIES: { value: ActivityType; label: string; icon: string }[] = [
  { value: "musculacao", label: "Musculação", icon: "🏋️" },
  { value: "cardio",     label: "Cardio",     icon: "❤️" },
  { value: "natacao",    label: "Natação",    icon: "🏊" },
  { value: "corrida",    label: "Corrida",    icon: "🏃" },
  { value: "funcional",  label: "Funcional",  icon: "⚡" },
  { value: "caminhada",  label: "Caminhada",  icon: "🚶" },
  { value: "hiit",       label: "HIIT",       icon: "🔥" },
];

const GENDERS: { value: Gender; label: string }[] = [
  { value: "male",         label: "Homem" },
  { value: "female",       label: "Mulher" },
  { value: "not_informed", label: "Prefiro não informar" },
];

const LOCATIONS: { value: TrainingLocation; label: string; desc: string; icon: string }[] = [
  { value: "gym",     label: "Academia",            desc: "Aparelhos, barras e halteres",    icon: "🏋️" },
  { value: "home",    label: "Em casa",             desc: "Sem equipamentos, peso corporal", icon: "🏠" },
  { value: "outdoor", label: "Ao ar livre",         desc: "Parques, ruas e quadras",         icon: "🌳" },
  { value: "any",     label: "Varia",               desc: "Depende do dia",                   icon: "🔄" },
];

export default function OnboardingPage() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState<FormData>({
    goal: "",
    fitness_level: "",
    age: "30",
    weight_kg: "75",
    height_cm: "175",
    gender: "",
    activity_preferences: [],
    training_location: "",
  });

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
  }, []);

  function set<K extends keyof FormData>(key: K, value: FormData[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function toggleActivity(act: ActivityType) {
    const current = form.activity_preferences;
    set(
      "activity_preferences",
      current.includes(act) ? current.filter((a) => a !== act) : [...current, act]
    );
  }

  async function handleFinish(location?: TrainingLocation) {
    setError("");
    setLoading(true);
    try {
      await api.post("/api/v1/health_profile", {
        goal: form.goal,
        fitness_level: form.fitness_level,
        age: Number(form.age),
        weight_kg: Number(form.weight_kg),
        height_cm: Number(form.height_cm),
        gender: form.gender || null,
        activity_preferences: form.activity_preferences,
        training_location: location || form.training_location || "gym",
      });
      trackEvent(EVENTS.ONBOARDING_COMPLETED);
      router.push("/plan");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erro ao salvar perfil");
    } finally {
      setLoading(false);
    }
  }

  const STEP_LABELS = ["goal", "level", "body", "activities", "location"];

  function goToStep(n: number) {
    setStep(n);
    trackEvent(EVENTS.ONBOARDING_STEP, { step: n, label: STEP_LABELS[n - 1] });
  }

  const TOTAL_STEPS = 5;

  return (
    <div className="flex min-h-screen flex-col px-4 py-8" style={{ background: "#0a0f1e" }}>
      <div className="mb-8 flex gap-1">
        {Array.from({ length: TOTAL_STEPS }, (_, i) => i + 1).map((n) => (
          <div
            key={n}
            className={`h-1 flex-1 rounded-full transition-colors ${
              n <= step ? "bg-primary-500" : "bg-slate-800"
            }`}
          />
        ))}
      </div>

      {step === 1 && (
        <StepGoal
          selected={form.goal}
          onSelect={(v) => { set("goal", v); goToStep(2); }}
        />
      )}

      {step === 2 && (
        <StepLevel
          selected={form.fitness_level}
          onSelect={(v) => { set("fitness_level", v); goToStep(3); }}
          onBack={() => goToStep(1)}
        />
      )}

      {step === 3 && (
        <StepBody
          form={form}
          onChange={set}
          onNext={() => goToStep(4)}
          onBack={() => goToStep(2)}
        />
      )}

      {step === 4 && (
        <StepActivities
          selected={form.activity_preferences}
          onToggle={toggleActivity}
          onNext={() => goToStep(5)}
          onBack={() => goToStep(3)}
        />
      )}

      {step === 5 && (
        <StepLocation
          selected={form.training_location}
          error={error}
          loading={loading}
          onSelect={(v) => { set("training_location", v); handleFinish(v); }}
          onBack={() => goToStep(4)}
        />
      )}
    </div>
  );
}

function StepGoal({ selected, onSelect }: { selected: string; onSelect: (v: Goal) => void }) {
  return (
    <div className="flex flex-1 flex-col">
      <h2 className="mb-2 text-xl font-bold text-white">Qual é o seu objetivo?</h2>
      <p className="mb-6 text-sm text-slate-400">Isso define seu plano de treino.</p>
      <div className="space-y-3">
        {GOALS.map((g) => (
          <button
            key={g.value}
            onClick={() => onSelect(g.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === g.value
                ? "border-primary-500 bg-primary-500/12"
                : "border-slate-800 bg-slate-900 hover:border-slate-600"
            }`}
          >
            <p className="font-semibold text-white">{g.label}</p>
            <p className="text-sm text-gray-500">{g.desc}</p>
          </button>
        ))}
      </div>
    </div>
  );
}

function StepLevel({
  selected,
  onSelect,
  onBack,
}: {
  selected: string;
  onSelect: (v: FitnessLevel) => void;
  onBack: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-slate-500 hover:text-slate-300">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-white">Seu nível de condicionamento?</h2>
      <p className="mb-6 text-sm text-slate-400">Seja honesto — isso ajusta a intensidade.</p>
      <div className="space-y-3">
        {LEVELS.map((l) => (
          <button
            key={l.value}
            onClick={() => onSelect(l.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === l.value
                ? "border-primary-500 bg-primary-500/12"
                : "border-slate-800 bg-slate-900 hover:border-slate-600"
            }`}
          >
            <p className="font-semibold text-white">{l.label}</p>
            <p className="text-sm text-gray-500">{l.desc}</p>
          </button>
        ))}
      </div>
    </div>
  );
}

function StepBody({
  form,
  onChange,
  onNext,
  onBack,
}: {
  form: FormData;
  onChange: <K extends keyof FormData>(key: K, value: FormData[K]) => void;
  onNext: () => void;
  onBack: () => void;
}) {
  const valid = !!form.gender;

  const sliders: { label: string; key: "age" | "weight_kg" | "height_cm"; unit: string; min: number; max: number }[] = [
    { label: "Idade",  key: "age",       unit: "anos", min: 14,  max: 90  },
    { label: "Peso",   key: "weight_kg", unit: "kg",   min: 35,  max: 180 },
    { label: "Altura", key: "height_cm", unit: "cm",   min: 120, max: 220 },
  ];

  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-slate-500 hover:text-slate-300">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-white">Seus dados físicos</h2>
      <p className="mb-6 text-sm text-slate-400">Usados para personalizar sua experiência.</p>

      <div className="space-y-6">
        <div>
          <label className="mb-3 block text-sm font-medium text-slate-400">
            Como você se identifica?
          </label>
          <div className="flex gap-2">
            {GENDERS.map((g) => (
              <button
                key={g.value}
                onClick={() => onChange("gender", g.value)}
                className={`flex-1 rounded-xl border-2 px-2 py-3 text-center text-sm font-medium transition ${
                  form.gender === g.value
                    ? "border-primary-500 bg-primary-500/12 text-primary-400"
                    : "border-slate-800 bg-slate-900 text-slate-400 hover:border-slate-600"
                }`}
              >
                {g.label}
              </button>
            ))}
          </div>
        </div>

        {sliders.map(({ label, key, unit, min, max }) => {
          const value = Number(form[key]);
          return (
            <div key={key}>
              <div className="mb-2 flex items-baseline justify-between">
                <label className="text-sm font-medium text-slate-400">{label}</label>
                <span className="text-2xl font-bold text-primary-500">
                  {value}
                  <span className="ml-1 text-sm font-normal text-slate-400">{unit}</span>
                </span>
              </div>
              <input
                type="range"
                min={min}
                max={max}
                step={1}
                value={form[key]}
                onChange={(e) => onChange(key, e.target.value)}
                className="w-full cursor-pointer"
                style={{ accentColor: "var(--color-primary-500)" }}
              />
              <div className="mt-1 flex justify-between text-xs text-slate-600">
                <span>{min} {unit}</span>
                <span>{max} {unit}</span>
              </div>
            </div>
          );
        })}
      </div>

      <button
        onClick={onNext}
        disabled={!valid}
        className="mt-8 w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
      >
        Continuar →
      </button>
    </div>
  );
}

function StepActivities({
  selected,
  onToggle,
  onNext,
  onBack,
}: {
  selected: ActivityType[];
  onToggle: (v: ActivityType) => void;
  onNext: () => void;
  onBack: () => void;
}) {
  const [attempted, setAttempted] = useState(false);

  function handleNext() {
    if (selected.length === 0) { setAttempted(true); return; }
    onNext();
  }

  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-slate-500 hover:text-slate-300">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-white">O que você gosta de fazer?</h2>
      <p className="mb-6 text-sm text-slate-400">Selecione pelo menos uma atividade.</p>

      <div className="grid grid-cols-2 gap-3">
        {ACTIVITIES.map((a) => {
          const isSelected = selected.includes(a.value);
          return (
            <button
              key={a.value}
              onClick={() => { onToggle(a.value); setAttempted(false); }}
              className={`flex items-center gap-3 rounded-xl border-2 p-4 text-left transition ${
                isSelected
                  ? "border-primary-500 bg-primary-500/12"
                  : "border-slate-800 bg-slate-900 hover:border-slate-600"
              }`}
            >
              <span className="text-xl leading-none">{a.icon}</span>
              <span className="text-sm font-medium text-white">{a.label}</span>
            </button>
          );
        })}
      </div>

      {attempted && selected.length === 0 && (
        <p className="mt-4 text-sm text-red-400">Selecione pelo menos uma atividade para continuar.</p>
      )}

      <button
        onClick={handleNext}
        className="mt-8 w-full rounded-full bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600"
      >
        Continuar →
      </button>
    </div>
  );
}

function StepLocation({
  selected,
  onSelect,
  error,
  loading,
  onBack,
}: {
  selected: TrainingLocation | "";
  onSelect: (v: TrainingLocation) => void;
  error: string;
  loading: boolean;
  onBack: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-slate-500 hover:text-slate-300">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-white">Onde você costuma treinar?</h2>
      <p className="mb-6 text-sm text-slate-400">Isso adapta os exercícios do seu plano.</p>

      {error && (
        <p className="mb-4 rounded-xl border border-red-800 bg-red-950/40 px-4 py-3 text-sm text-red-400">{error}</p>
      )}

      <div className="space-y-3">
        {LOCATIONS.map((l) => (
          <button
            key={l.value}
            onClick={() => onSelect(l.value)}
            disabled={loading}
            className={`w-full rounded-xl border-2 p-4 text-left transition disabled:opacity-70 ${
              selected === l.value
                ? "border-primary-500 bg-primary-500/12"
                : "border-slate-800 bg-slate-900 hover:border-slate-600"
            }`}
          >
            <div className="flex items-center gap-3">
              <span className="text-xl leading-none">{l.icon}</span>
              <div>
                <p className="font-semibold text-white">{l.label}</p>
                <p className="text-sm text-gray-500">{l.desc}</p>
              </div>
            </div>
          </button>
        ))}
      </div>

      {loading && (
        <p className="mt-4 text-center text-sm text-slate-400">Criando seu plano...</p>
      )}
    </div>
  );
}
