"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import type { Goal, FitnessLevel, ActivityType } from "@/shared/types/health-profile";

interface FormData {
  goal: Goal | "";
  fitness_level: FitnessLevel | "";
  age: string;
  weight_kg: string;
  height_cm: string;
  activity_preferences: ActivityType[];
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

export default function OnboardingPage() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState<FormData>({
    goal: "",
    fitness_level: "",
    age: "",
    weight_kg: "",
    height_cm: "",
    activity_preferences: [],
  });

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

  async function handleFinish() {
    setError("");
    setLoading(true);
    try {
      await api.post("/api/v1/health_profile", {
        goal: form.goal,
        fitness_level: form.fitness_level,
        age: Number(form.age),
        weight_kg: Number(form.weight_kg),
        height_cm: Number(form.height_cm),
        activity_preferences: form.activity_preferences,
      });
      router.push("/plan");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erro ao salvar perfil");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col px-4 py-8">
      <div className="mb-8 flex gap-1">
        {[1, 2, 3, 4].map((n) => (
          <div
            key={n}
            className={`h-1 flex-1 rounded-full transition-colors ${
              n <= step ? "bg-green-500" : "bg-gray-200"
            }`}
          />
        ))}
      </div>

      {step === 1 && (
        <StepGoal
          selected={form.goal}
          onSelect={(v) => { set("goal", v); setStep(2); }}
        />
      )}

      {step === 2 && (
        <StepLevel
          selected={form.fitness_level}
          onSelect={(v) => { set("fitness_level", v); setStep(3); }}
          onBack={() => setStep(1)}
        />
      )}

      {step === 3 && (
        <StepBody
          form={form}
          onChange={set}
          onNext={() => setStep(4)}
          onBack={() => setStep(2)}
        />
      )}

      {step === 4 && (
        <StepActivities
          selected={form.activity_preferences}
          onToggle={toggleActivity}
          error={error}
          loading={loading}
          onFinish={handleFinish}
          onBack={() => setStep(3)}
        />
      )}
    </div>
  );
}

function StepGoal({ selected, onSelect }: { selected: string; onSelect: (v: Goal) => void }) {
  return (
    <div className="flex flex-1 flex-col">
      <h2 className="mb-2 text-xl font-bold text-gray-900">Qual é o seu objetivo?</h2>
      <p className="mb-6 text-sm text-gray-500">Isso define seu plano de treino.</p>
      <div className="space-y-3">
        {GOALS.map((g) => (
          <button
            key={g.value}
            onClick={() => onSelect(g.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === g.value
                ? "border-green-500 bg-green-50"
                : "border-gray-200 hover:border-gray-300"
            }`}
          >
            <p className="font-semibold text-gray-900">{g.label}</p>
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
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900">Seu nível de condicionamento?</h2>
      <p className="mb-6 text-sm text-gray-500">Seja honesto — isso ajusta a intensidade.</p>
      <div className="space-y-3">
        {LEVELS.map((l) => (
          <button
            key={l.value}
            onClick={() => onSelect(l.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === l.value
                ? "border-green-500 bg-green-50"
                : "border-gray-200 hover:border-gray-300"
            }`}
          >
            <p className="font-semibold text-gray-900">{l.label}</p>
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
  const valid = form.age && form.weight_kg && form.height_cm;

  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900">Seus dados físicos</h2>
      <p className="mb-6 text-sm text-gray-500">Usados para personalizar sua experiência.</p>

      <div className="space-y-4">
        {[
          { label: "Idade",  key: "age" as const,       placeholder: "Ex: 28", unit: "anos", min: "1",  max: "119" },
          { label: "Peso",   key: "weight_kg" as const, placeholder: "Ex: 75", unit: "kg",   min: "1",  max: "500" },
          { label: "Altura", key: "height_cm" as const, placeholder: "Ex: 175", unit: "cm",  min: "50", max: "300" },
        ].map(({ label, key, placeholder, unit, min, max }) => (
          <div key={key}>
            <label className="mb-1 block text-sm font-medium text-gray-700">{label}</label>
            <div className="flex">
              <input
                type="number"
                value={form[key]}
                onChange={(e) => onChange(key, e.target.value)}
                min={min}
                max={max}
                placeholder={placeholder}
                className="flex-1 rounded-l-lg border border-r-0 border-gray-300 px-4 py-3 text-sm focus:border-green-500 focus:outline-none"
              />
              <span className="flex items-center rounded-r-lg border border-gray-300 bg-gray-50 px-3 text-sm text-gray-500">
                {unit}
              </span>
            </div>
          </div>
        ))}
      </div>

      <button
        onClick={onNext}
        disabled={!valid}
        className="mt-8 w-full rounded-lg bg-green-500 py-3 text-sm font-semibold text-white transition hover:bg-green-600 disabled:opacity-50"
      >
        Continuar →
      </button>
    </div>
  );
}

function StepActivities({
  selected,
  onToggle,
  error,
  loading,
  onFinish,
  onBack,
}: {
  selected: ActivityType[];
  onToggle: (v: ActivityType) => void;
  error: string;
  loading: boolean;
  onFinish: () => void;
  onBack: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900">O que você gosta de fazer?</h2>
      <p className="mb-6 text-sm text-gray-500">Selecione pelo menos uma atividade.</p>

      {error && (
        <p className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
      )}

      <div className="grid grid-cols-2 gap-3">
        {ACTIVITIES.map((a) => {
          const isSelected = selected.includes(a.value);
          return (
            <button
              key={a.value}
              onClick={() => onToggle(a.value)}
              className={`flex items-center gap-3 rounded-xl border-2 p-4 text-left transition ${
                isSelected
                  ? "border-green-500 bg-green-50"
                  : "border-gray-200 hover:border-gray-300"
              }`}
            >
              <span className="text-xl leading-none">{a.icon}</span>
              <span className="text-sm font-medium text-gray-900">{a.label}</span>
            </button>
          );
        })}
      </div>

      <button
        onClick={onFinish}
        disabled={selected.length === 0 || loading}
        className="mt-8 w-full rounded-lg bg-green-500 py-3 text-sm font-semibold text-white transition hover:bg-green-600 disabled:opacity-50"
      >
        {loading ? "Criando plano..." : "Criar meu plano →"}
      </button>
    </div>
  );
}
