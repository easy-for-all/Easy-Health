"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { OptionCard } from "@/shared/components/ui/option-card";
import { ExercisePreferencePicker } from "@/features/profile/exercise-preference-picker";
import type {
  BodyFocus,
  Equipment,
  ExercisePreference,
  FitnessLevel,
  Gender,
  Goal,
  IntensityPreference,
  TrainingContext,
  TrainingLocation,
  TrainingStyle,
} from "@/shared/types/health-profile";
import "@/shared/components/ui/ui.css";

type Duration = 15 | 25 | 35 | 45 | 60;

interface FormData {
  goal: Goal | "";
  fitness_level: FitnessLevel | "";
  age: string;
  weight_kg: string;
  height_cm: string;
  gender: Gender | "";
  preferred_body_focus: BodyFocus[];
  preferred_training_styles: TrainingStyle[];
  training_location: TrainingLocation | "";
  available_equipment: Equipment[];
  session_duration_minutes: Duration | null;
  training_days_per_week: number | null;
  intensity_preference: IntensityPreference | "";
  favorite_exercises: ExercisePreference[];
  avoided_exercises: ExercisePreference[];
  limitations: string[];
  training_context: TrainingContext | "";
}

const GOALS: { value: Goal; label: string; desc: string; icon: string }[] = [
  { value: "lose_weight", label: "Emagrecer", desc: "Reduzir gordura corporal", icon: "🔥" },
  { value: "gain_muscle", label: "Ganhar massa muscular", desc: "Construir massa muscular", icon: "💪" },
  { value: "body_definition", label: "Definir o corpo", desc: "Buscar mais definição", icon: "✨" },
  { value: "conditioning", label: "Melhorar condicionamento", desc: "Ter mais fôlego e resistência", icon: "🏃" },
  { value: "strength", label: "Ganhar força", desc: "Evoluir cargas e capacidade", icon: "🏋️" },
  { value: "mobility", label: "Melhorar mobilidade", desc: "Mover-se com mais conforto", icon: "🧘" },
  { value: "safe_return", label: "Voltar com segurança", desc: "Retomar aos poucos", icon: "🛟" },
  { value: "health_longevity", label: "Saúde e longevidade", desc: "Cuidar do corpo no longo prazo", icon: "❤️" },
];

const LEVELS: { value: FitnessLevel; label: string; desc: string; icon: string }[] = [
  { value: "beginner", label: "Iniciante", desc: "Menos de 6 meses de treino", icon: "🌱" },
  { value: "intermediate", label: "Intermediário", desc: "6 meses a 2 anos", icon: "🎯" },
  { value: "advanced", label: "Avançado", desc: "Mais de 2 anos", icon: "⚡" },
];

const BODY_FOCUS: { value: BodyFocus; label: string }[] = [
  { value: "full_body", label: "Corpo inteiro" }, { value: "glutes", label: "Glúteos" },
  { value: "legs", label: "Pernas" }, { value: "abs", label: "Abdômen" },
  { value: "arms", label: "Braços" }, { value: "chest", label: "Peito" },
  { value: "back", label: "Costas" }, { value: "shoulders", label: "Ombros" },
  { value: "mobility_posture", label: "Mobilidade/postura" }, { value: "conditioning_cardio", label: "Condicionamento/cardio" },
];

const TRAINING_STYLES: { value: TrainingStyle; label: string }[] = [
  { value: "traditional_strength", label: "Musculação tradicional" }, { value: "short_sessions", label: "Treinos curtos e objetivos" },
  { value: "cardio", label: "Cardio" }, { value: "functional", label: "Funcional" },
  { value: "calisthenics", label: "Calistenia" }, { value: "mobility", label: "Mobilidade/alongamento" },
  { value: "mixed", label: "Misturado" }, { value: "unknown", label: "Não sei ainda" },
];

const LOCATIONS: { value: TrainingLocation; label: string; desc: string; icon: string }[] = [
  { value: "full_gym", label: "Academia completa", desc: "Máquinas, pesos e acessórios", icon: "🏋️" },
  { value: "simple_gym", label: "Academia simples", desc: "Estrutura essencial", icon: "🏢" },
  { value: "home", label: "Casa", desc: "Seu espaço", icon: "🏠" },
  { value: "condo", label: "Condomínio", desc: "Área comum ou academia", icon: "🏙️" },
  { value: "outdoor", label: "Ar livre", desc: "Parques e ruas", icon: "🌳" },
  { value: "hotel_travel", label: "Hotel/viagem", desc: "Rotina em movimento", icon: "🧳" },
  { value: "unknown", label: "Ainda não sei", desc: "Definimos depois", icon: "🔄" },
];

const EQUIPMENT: { value: Equipment; label: string }[] = [
  { value: "machine", label: "Máquinas" }, { value: "dumbbell", label: "Halteres" },
  { value: "barbell", label: "Barra" }, { value: "plates", label: "Anilhas" },
  { value: "resistance_band", label: "Elásticos" }, { value: "treadmill", label: "Esteira" },
  { value: "stationary_bike", label: "Bicicleta" }, { value: "rower", label: "Remo" },
  { value: "jump_rope", label: "Corda" }, { value: "bodyweight", label: "Peso corporal apenas" },
  { value: "none", label: "Nenhum" },
];

const INTENSITIES: { value: IntensityPreference; label: string }[] = [
  { value: "easy_start", label: "Fáceis de começar" }, { value: "balanced", label: "Equilibrados" },
  { value: "intense", label: "Intensos" }, { value: "progressive", label: "Progressivos" },
  { value: "unknown", label: "Não sei" },
];

const LIMITATION_PRESETS = ["Joelho", "Lombar", "Ombro", "Punho", "Pescoço", "Quadril", "Pós-parto", "Retorno de lesão"];

function Screen({ step, children }: { step: number; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: "100svh", background: "var(--bg)", color: "var(--text)", padding: "52px 20px 32px" }}>
      <div className="progress-dots" style={{ marginBottom: 28 }}>
        {Array.from({ length: 7 }, (_, index) => <i key={index} className={index < step ? "on" : index === step - 1 ? "cur" : ""} />)}
      </div>
      {children}
    </div>
  );
}

function BackBtn({ onClick }: { onClick: () => void }) {
  return <button onClick={onClick} className="wizard-back">← Voltar</button>;
}

function ChoiceGrid<T extends string>({ values, selected, onToggle, limit }: {
  values: { value: T; label: string }[];
  selected: T[];
  onToggle: (value: T) => void;
  limit?: number;
}) {
  return (
    <div className="opt-grid">
      {values.map((item) => {
        const active = selected.includes(item.value);
        const blocked = !active && !!limit && selected.length >= limit;
        return (
          <button key={item.value} type="button" disabled={blocked} className={`opt${active ? " sel" : ""}`} onClick={() => onToggle(item.value)}>
            <span className="otxt"><b>{item.label}</b></span>
          </button>
        );
      })}
    </div>
  );
}

export default function OnboardingPage() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [customLimitation, setCustomLimitation] = useState("");
  const [form, setForm] = useState<FormData>({
    goal: "", fitness_level: "", age: "30", weight_kg: "75", height_cm: "175", gender: "",
    preferred_body_focus: [], preferred_training_styles: [], training_location: "", available_equipment: [],
    session_duration_minutes: null, training_days_per_week: null, intensity_preference: "",
    favorite_exercises: [], avoided_exercises: [], limitations: [], training_context: "",
  });

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
  }, []);

  function set<K extends keyof FormData>(key: K, value: FormData[K]) {
    setForm((previous) => ({ ...previous, [key]: value }));
  }

  function toggleList<K extends "preferred_body_focus" | "available_equipment" | "limitations">(key: K, value: FormData[K][number], limit?: number) {
    const current = form[key] as string[];
    if (current.includes(value as string)) {
      set(key, current.filter((item) => item !== value) as FormData[K]);
      return;
    }
    if (limit && current.length >= limit) return;
    if (key === "available_equipment" && value === "none") {
      set(key, [value] as FormData[K]);
      return;
    }
    const next = key === "available_equipment" ? current.filter((item) => item !== "none") : current;
    set(key, [...next, value] as FormData[K]);
  }

  function goToStep(next: number) {
    setStep(next);
    trackEvent(EVENTS.ONBOARDING_STEP, { step: next });
  }

  function addCustomLimitation() {
    const value = customLimitation.trim();
    if (value && !form.limitations.includes(value)) set("limitations", [...form.limitations, value]);
    setCustomLimitation("");
  }

  async function handleFinish() {
    setError("");
    setLoading(true);

    const payload = {
      goal: form.goal,
      fitness_level: form.fitness_level,
      age: Number(form.age),
      weight_kg: Number(form.weight_kg),
      height_cm: Number(form.height_cm),
      gender: form.gender || null,
      preferred_body_focus: form.preferred_body_focus,
      preferred_training_styles: form.preferred_training_styles,
      training_location: form.training_location || "unknown",
      available_equipment: form.available_equipment,
      session_duration_minutes: form.session_duration_minutes,
      training_days_per_week: form.training_days_per_week,
      intensity_preference: form.intensity_preference || null,
      favorite_exercise_ids: form.favorite_exercises.map((exercise) => exercise.id),
      avoided_exercise_ids: form.avoided_exercises.map((exercise) => exercise.id),
      limitations: form.limitations,
      training_context: form.gender === "female" ? form.training_context || null : null,
    };

    try {
      try {
        await api.post("/api/v1/health_profile", payload);
      } catch (postErr: unknown) {
        const status = (postErr as { status?: number })?.status;
        if (status === 422) {
          await api.patch("/api/v1/health_profile", payload);
        } else {
          throw postErr;
        }
      }
      trackEvent(EVENTS.ONBOARDING_COMPLETED);
      router.push("/plan?from_onboarding=1");
    } catch {
      setLoading(false);
      setError("Não conseguimos salvar seu perfil. Tente novamente em instantes.");
    }
  }

  if (step === 1) return <Screen step={1}>
    <h2 className="wizard-title">Qual é seu objetivo principal agora?</h2>
    <p className="wizard-sub">Isso orienta seu plano desde o começo.</p>
    <div className="opts">{GOALS.map((goal) => <OptionCard key={goal.value} icon={goal.icon} label={goal.label} description={goal.desc} selected={form.goal === goal.value} onClick={() => { set("goal", goal.value); goToStep(2); }} />)}</div>
  </Screen>;

  if (step === 2) return <Screen step={2}>
    <BackBtn onClick={() => goToStep(1)} />
    <h2 className="wizard-title">Seu nível e seus dados físicos</h2>
    <p className="wizard-sub">Usamos isso para ajustar a intensidade com segurança.</p>
    <div className="opts">{LEVELS.map((level) => <OptionCard key={level.value} icon={level.icon} label={level.label} description={level.desc} selected={form.fitness_level === level.value} onClick={() => set("fitness_level", level.value)} />)}</div>
    <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 20 }}>
      <div className="segmented">{([ ["male", "Homem"], ["female", "Mulher"], ["not_informed", "Prefiro não informar"] ] as [Gender, string][]).map(([value, label]) => <button key={value} type="button" className={form.gender === value ? "sel" : ""} onClick={() => set("gender", value)}>{label}</button>)}</div>
      {(["age", "weight_kg", "height_cm"] as const).map((key) => {
        const details = { age: ["Idade", "anos", 14, 90], weight_kg: ["Peso", "kg", 35, 180], height_cm: ["Altura", "cm", 120, 220] }[key];
        return <div key={key} className="slide-row"><div className="lab"><span>{details[0]}</span><b>{form[key]}<em>{details[1]}</em></b></div><input type="range" min={details[2]} max={details[3]} value={form[key]} onChange={(event) => set(key, event.target.value)} /></div>;
      })}
    </div>
    <button className="wizard-cta" style={{ marginTop: 24 }} disabled={!form.fitness_level} onClick={() => goToStep(3)}>Continuar →</button>
  </Screen>;

  if (step === 3) return <Screen step={3}>
    <BackBtn onClick={() => goToStep(2)} />
    <h2 className="wizard-title">O que você quer desenvolver?</h2>
    <p className="wizard-sub">Escolha até três focos — ou pule por enquanto.</p>
    <ChoiceGrid values={BODY_FOCUS} selected={form.preferred_body_focus} limit={3} onToggle={(value) => toggleList("preferred_body_focus", value, 3)} />
    <button className="wizard-cta" style={{ marginTop: 24 }} onClick={() => goToStep(4)}>Continuar →</button>
    <button className="wizard-back" onClick={() => goToStep(4)}>Pular agora</button>
  </Screen>;

  if (step === 4) return <Screen step={4}>
    <BackBtn onClick={() => goToStep(3)} />
    <h2 className="wizard-title">Qual estilo de treino você prefere?</h2>
    <p className="wizard-sub">Você pode mudar essa preferência depois.</p>
    <div className="opts">{TRAINING_STYLES.map((style) => <OptionCard key={style.value} icon="✦" label={style.label} selected={form.preferred_training_styles[0] === style.value} onClick={() => { set("preferred_training_styles", [style.value]); goToStep(5); }} />)}</div>
    <button className="wizard-back" onClick={() => goToStep(5)}>Pular agora</button>
  </Screen>;

  if (step === 5) return <Screen step={5}>
    <BackBtn onClick={() => goToStep(4)} />
    <h2 className="wizard-title">Onde e com o que você treina?</h2>
    <p className="wizard-sub">Assim respeitamos sua realidade, sem adivinhação.</p>
    <div className="opts">{LOCATIONS.map((location) => <OptionCard key={location.value} icon={location.icon} label={location.label} description={location.desc} selected={form.training_location === location.value} onClick={() => set("training_location", location.value)} />)}</div>
    <p className="wizard-sub" style={{ marginTop: 20 }}>Equipamentos disponíveis</p>
    <ChoiceGrid values={EQUIPMENT} selected={form.available_equipment} onToggle={(value) => toggleList("available_equipment", value)} />
    <button className="wizard-cta" style={{ marginTop: 24 }} onClick={() => goToStep(6)}>Continuar →</button>
  </Screen>;

  if (step === 6) return <Screen step={6}>
    <BackBtn onClick={() => goToStep(5)} />
    <h2 className="wizard-title">Como cabe na sua rotina?</h2>
    <p className="wizard-sub">Tudo aqui é opcional e ajustável depois.</p>
    <p className="wizard-sub">Tempo por treino</p>
    <ChoiceGrid values={([15, 25, 35, 45, 60] as Duration[]).map((value) => ({ value: String(value), label: value === 60 ? "60 minutos ou mais" : `${value} minutos` }))} selected={form.session_duration_minutes ? [String(form.session_duration_minutes)] : []} onToggle={(value) => set("session_duration_minutes", Number(value) as Duration)} />
    <p className="wizard-sub" style={{ marginTop: 18 }}>Vezes por semana</p>
    <ChoiceGrid values={[1, 2, 3, 4, 5, 6].map((value) => ({ value: String(value), label: value === 6 ? "6x ou mais" : `${value}x` }))} selected={form.training_days_per_week ? [String(form.training_days_per_week)] : []} onToggle={(value) => set("training_days_per_week", Number(value))} />
    <p className="wizard-sub" style={{ marginTop: 18 }}>Você prefere treinos mais…</p>
    <ChoiceGrid values={INTENSITIES} selected={form.intensity_preference ? [form.intensity_preference] : []} onToggle={(value) => set("intensity_preference", value)} />
    <button className="wizard-cta" style={{ marginTop: 24 }} onClick={() => goToStep(7)}>Continuar →</button>
  </Screen>;

  return <Screen step={7}>
    <BackBtn onClick={() => goToStep(6)} />
    <h2 className="wizard-title">Preferências e cuidados</h2>
    <p className="wizard-sub">Essas respostas são opcionais e deixam seu treino mais pessoal.</p>
    <div style={{ display: "grid", gap: 18 }}>
      <ExercisePreferencePicker label="Exercícios que você gosta" hint="Busque e selecione seus favoritos." selected={form.favorite_exercises} onChange={(exercises) => set("favorite_exercises", exercises)} />
      <ExercisePreferencePicker label="Exercícios que quer evitar" hint="Não vamos priorizá-los nas próximas estratégias." selected={form.avoided_exercises} onChange={(exercises) => set("avoided_exercises", exercises)} />
      <div><label className="mb-2 block text-sm font-medium text-slate-300">Alguma limitação ou cuidado?</label><button type="button" onClick={() => set("limitations", [])} className={`mb-2 rounded-full border px-3 py-1.5 text-xs font-semibold ${form.limitations.length === 0 ? "border-primary-500 bg-primary-500 text-white" : "border-slate-700 bg-slate-800 text-slate-300"}`}>Nenhuma</button><ChoiceGrid values={LIMITATION_PRESETS.map((value) => ({ value, label: value }))} selected={form.limitations} onToggle={(value) => toggleList("limitations", value)} /><div style={{ display: "flex", gap: 8, marginTop: 8 }}><input value={customLimitation} onChange={(event) => setCustomLimitation(event.target.value)} placeholder="Outro cuidado" className="flex-1 rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-white" /><button type="button" onClick={addCustomLimitation} className="rounded-xl border border-slate-700 px-3 text-sm text-slate-200">Adicionar</button></div></div>
      {form.gender === "female" && <div><label className="mb-2 block text-sm font-medium text-slate-300">Existe algum contexto que devemos considerar?</label><ChoiceGrid values={([ ["none", "Nenhum"], ["postpartum", "Pós-parto"], ["pregnant", "Gestante"], ["menstrual_cycle_impact", "Ciclo menstrual impacta meus treinos"], ["prefer_not_to_say", "Prefiro não informar"] ] as [TrainingContext, string][]).map(([value, label]) => ({ value, label }))} selected={form.training_context ? [form.training_context] : []} onToggle={(value) => set("training_context", value)} /></div>}
    </div>
    <p style={{ marginTop: 18, fontSize: 12, color: "var(--text-muted)" }}>A EasyHealth não substitui orientação médica. Se você sente dor ou tem condição de saúde, consulte um profissional.</p>
    {error && <p style={{ marginTop: 12, color: "var(--hot)", fontSize: 13 }}>{error}</p>}
    <button className="wizard-cta" style={{ marginTop: 20 }} disabled={loading} onClick={handleFinish}>{loading ? "Criando seu plano…" : "Criar meu plano"}</button>
  </Screen>;
}
