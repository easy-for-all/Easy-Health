"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { compressImage } from "@/shared/lib/image";
import type { Goal, FitnessLevel, ActivityType } from "@/shared/types/health-profile";

type TrainingLocation = "gym" | "home" | "outdoor" | "any";

interface FormData {
  goal: Goal | "";
  fitness_level: FitnessLevel | "";
  age: string;
  weight_kg: string;
  height_cm: string;
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
    age: "",
    weight_kg: "",
    height_cm: "",
    activity_preferences: [],
    training_location: "",
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
        training_location: form.training_location || "gym",
      });
      setStep(6);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erro ao salvar perfil");
    } finally {
      setLoading(false);
    }
  }

  async function handlePhotoFinish(file: File | null) {
    if (file) {
      try {
        const compressed = await compressImage(file, 1920, 0.85);
        const formData = new FormData();
        formData.append("file", compressed);
        formData.append("category", "body_photo");
        await api.uploadPost("/api/v1/user_media", formData);
      } catch {
        // upload failure is non-blocking — proceed to plan
      }
    }
    router.push("/plan");
  }

  const TOTAL_STEPS = 6;

  return (
    <div className="flex min-h-screen flex-col bg-white px-4 py-8 dark:bg-gray-950">
      <div className="mb-8 flex gap-1">
        {Array.from({ length: TOTAL_STEPS }, (_, i) => i + 1).map((n) => (
          <div
            key={n}
            className={`h-1 flex-1 rounded-full transition-colors ${
              n <= step ? "bg-primary-500" : "bg-gray-200 dark:bg-gray-800"
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
          onNext={() => setStep(5)}
          onBack={() => setStep(3)}
        />
      )}

      {step === 5 && (
        <StepLocation
          selected={form.training_location}
          onSelect={(v) => set("training_location", v)}
          error={error}
          loading={loading}
          onFinish={handleFinish}
          onBack={() => setStep(4)}
        />
      )}

      {step === 6 && (
        <StepPhoto onFinish={handlePhotoFinish} />
      )}
    </div>
  );
}

function StepGoal({ selected, onSelect }: { selected: string; onSelect: (v: Goal) => void }) {
  return (
    <div className="flex flex-1 flex-col">
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">Qual é o seu objetivo?</h2>
      <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">Isso define seu plano de treino.</p>
      <div className="space-y-3">
        {GOALS.map((g) => (
          <button
            key={g.value}
            onClick={() => onSelect(g.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === g.value
                ? "border-primary-500 bg-primary-50 dark:bg-primary-950/40"
                : "border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600"
            }`}
          >
            <p className="font-semibold text-gray-900 dark:text-gray-50">{g.label}</p>
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
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">Seu nível de condicionamento?</h2>
      <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">Seja honesto — isso ajusta a intensidade.</p>
      <div className="space-y-3">
        {LEVELS.map((l) => (
          <button
            key={l.value}
            onClick={() => onSelect(l.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === l.value
                ? "border-primary-500 bg-primary-50 dark:bg-primary-950/40"
                : "border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600"
            }`}
          >
            <p className="font-semibold text-gray-900 dark:text-gray-50">{l.label}</p>
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
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">Seus dados físicos</h2>
      <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">Usados para personalizar sua experiência.</p>

      <div className="space-y-4">
        {[
          { label: "Idade",  key: "age" as const,       placeholder: "Ex: 28", unit: "anos", min: "1",  max: "119" },
          { label: "Peso",   key: "weight_kg" as const, placeholder: "Ex: 75", unit: "kg",   min: "1",  max: "500" },
          { label: "Altura", key: "height_cm" as const, placeholder: "Ex: 175", unit: "cm",  min: "50", max: "300" },
        ].map(({ label, key, placeholder, unit, min, max }) => (
          <div key={key}>
            <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">{label}</label>
            <div className="flex">
              <input
                type="number"
                value={form[key]}
                onChange={(e) => onChange(key, e.target.value)}
                min={min}
                max={max}
                placeholder={placeholder}
                className="flex-1 rounded-l-lg border border-r-0 border-gray-300 bg-white px-4 py-3 text-sm text-gray-900 focus:border-primary-500 focus:outline-none dark:border-gray-700 dark:bg-gray-800 dark:text-gray-50"
              />
              <span className="flex items-center rounded-r-lg border border-gray-300 bg-gray-50 px-3 text-sm text-gray-500 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-400">
                {unit}
              </span>
            </div>
          </div>
        ))}
      </div>

      <button
        onClick={onNext}
        disabled={!valid}
        className="mt-8 w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
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
  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">O que você gosta de fazer?</h2>
      <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">Selecione pelo menos uma atividade.</p>

      <div className="grid grid-cols-2 gap-3">
        {ACTIVITIES.map((a) => {
          const isSelected = selected.includes(a.value);
          return (
            <button
              key={a.value}
              onClick={() => onToggle(a.value)}
              className={`flex items-center gap-3 rounded-xl border-2 p-4 text-left transition ${
                isSelected
                  ? "border-primary-500 bg-primary-50 dark:bg-primary-950/40"
                  : "border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600"
              }`}
            >
              <span className="text-xl leading-none">{a.icon}</span>
              <span className="text-sm font-medium text-gray-900 dark:text-gray-50">{a.label}</span>
            </button>
          );
        })}
      </div>

      <button
        onClick={onNext}
        disabled={selected.length === 0}
        className="mt-8 w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
      >
        Continuar →
      </button>
    </div>
  );
}

function StepPhoto({ onFinish }: { onFinish: (file: File | null) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0] ?? null;
    if (!file) return;
    setSelectedFile(file);
    setPreview(URL.createObjectURL(file));
  }

  async function handleSend() {
    setUploading(true);
    await onFinish(selectedFile);
    setUploading(false);
  }

  return (
    <div className="flex flex-1 flex-col">
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">Foto do perfil físico</h2>
      <p className="mb-1 text-sm text-gray-500">
        Quer enviar uma foto para ajudar a IA a entender melhor seu perfil físico? Isso é opcional.
      </p>
      <p className="mb-6 text-xs text-gray-400">Sua foto fica armazenada com segurança e não é compartilhada.</p>

      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={handleFileChange}
      />

      {preview ? (
        <div className="mb-4 flex flex-col items-center gap-3">
          <img src={preview} alt="preview" className="h-48 w-48 rounded-2xl object-cover shadow" />
          <button
            onClick={() => { setPreview(null); setSelectedFile(null); if (inputRef.current) inputRef.current.value = ""; }}
            className="text-xs text-gray-400 hover:text-gray-600"
          >
            Remover foto
          </button>
        </div>
      ) : (
        <button
          onClick={() => inputRef.current?.click()}
          className="mb-4 flex flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-gray-200 py-10 hover:border-primary-300 hover:bg-primary-50"
        >
          <span className="text-3xl">📷</span>
          <span className="text-sm font-medium text-gray-600">Escolher foto</span>
          <span className="text-xs text-gray-400">JPG, PNG ou HEIC</span>
        </button>
      )}

      <button
        onClick={handleSend}
        disabled={uploading}
        className="mt-2 w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
      >
        {uploading ? "Enviando..." : selectedFile ? "Enviar foto e continuar →" : "Continuar com foto →"}
      </button>
      <button
        onClick={() => onFinish(null)}
        disabled={uploading}
        className="mt-3 w-full py-2 text-sm text-gray-400 hover:text-gray-600 disabled:opacity-50"
      >
        Pular por enquanto
      </button>
    </div>
  );
}

function StepLocation({
  selected,
  onSelect,
  error,
  loading,
  onFinish,
  onBack,
}: {
  selected: TrainingLocation | "";
  onSelect: (v: TrainingLocation) => void;
  error: string;
  loading: boolean;
  onFinish: () => void;
  onBack: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
        ← Voltar
      </button>
      <h2 className="mb-2 text-xl font-bold text-gray-900 dark:text-gray-50">Onde você costuma treinar?</h2>
      <p className="mb-6 text-sm text-gray-500 dark:text-gray-400">Isso adapta os exercícios do seu plano.</p>

      {error && (
        <p className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
      )}

      <div className="space-y-3">
        {LOCATIONS.map((l) => (
          <button
            key={l.value}
            onClick={() => onSelect(l.value)}
            className={`w-full rounded-xl border-2 p-4 text-left transition ${
              selected === l.value
                ? "border-primary-500 bg-primary-50 dark:bg-primary-950/40"
                : "border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600"
            }`}
          >
            <div className="flex items-center gap-3">
              <span className="text-xl leading-none">{l.icon}</span>
              <div>
                <p className="font-semibold text-gray-900 dark:text-gray-50">{l.label}</p>
                <p className="text-sm text-gray-500">{l.desc}</p>
              </div>
            </div>
          </button>
        ))}
      </div>

      <button
        onClick={onFinish}
        disabled={!selected || loading}
        className="mt-8 w-full rounded-lg bg-primary-500 py-3 text-sm font-semibold text-white transition hover:bg-primary-600 disabled:opacity-50"
      >
        {loading ? "Criando plano..." : "Criar meu plano →"}
      </button>
    </div>
  );
}
