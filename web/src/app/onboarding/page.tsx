"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { OptionCard } from "@/shared/components/ui/option-card";
import "@/shared/components/ui/ui.css";
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

const GOALS: { value: Goal; label: string; desc: string; icon: string }[] = [
  { value: "lose_weight", label: "Emagrecimento",  desc: "Reduzir gordura corporal",          icon: "🔥" },
  { value: "gain_muscle", label: "Hipertrofia",    desc: "Ganhar massa muscular",              icon: "💪" },
  { value: "maintain",    label: "Manutenção",     desc: "Manter peso e composição",           icon: "⚖️" },
  { value: "health",      label: "Saúde geral",    desc: "Melhorar qualidade de vida",         icon: "❤️" },
];

const LEVELS: { value: FitnessLevel; label: string; desc: string; icon: string }[] = [
  { value: "beginner",     label: "Iniciante",     desc: "Menos de 6 meses de treino", icon: "🌱" },
  { value: "intermediate", label: "Intermediário", desc: "6 meses a 2 anos",           icon: "🎯" },
  { value: "advanced",     label: "Avançado",      desc: "Mais de 2 anos de treino",   icon: "⚡" },
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
  { value: "gym",     label: "Academia",    desc: "Aparelhos, barras e halteres",    icon: "🏋️" },
  { value: "home",    label: "Em casa",     desc: "Peso corporal, sem equipamentos", icon: "🏠" },
  { value: "outdoor", label: "Ao ar livre", desc: "Parques, ruas e quadras",         icon: "🌳" },
  { value: "any",     label: "Varia",       desc: "Depende do dia",                  icon: "🔄" },
];

// ── Shared layout ─────────────────────────────────────────────────────────────

function Screen({ step, total, children }: { step: number; total: number; children: React.ReactNode }) {
  return (
    <div
      style={{
        display: "flex", flexDirection: "column", minHeight: "100svh",
        background: "var(--bg)", color: "var(--text)",
        padding: "52px 20px 32px",
      }}
    >
      {/* Progress */}
      <div className="progress-dots" style={{ marginBottom: 28 }}>
        {Array.from({ length: total }, (_, i) => (
          <i key={i} className={i < step ? "on" : i === step - 1 ? "cur" : ""} />
        ))}
      </div>
      {children}
    </div>
  );
}

function BackBtn({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="wizard-back">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ width: 18, height: 18 }}>
        <polyline points="15 18 9 12 15 6" />
      </svg>
      Voltar
    </button>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function OnboardingPage() {
  const router = useRouter();
  const [step, setStep]     = useState(1);
  const [error, setError]   = useState("");
  const [loading, setLoading] = useState(false);
  const [form, setForm]     = useState<FormData>({
    goal: "", fitness_level: "",
    age: "30", weight_kg: "75", height_cm: "175",
    gender: "",
    activity_preferences: [],
    training_location: "",
  });

  useEffect(() => {
    trackEvent(EVENTS.ONBOARDING_STARTED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "onboarding" });
  }, []);

  function set<K extends keyof FormData>(key: K, value: FormData[K]) {
    setForm((p) => ({ ...p, [key]: value }));
  }

  function toggleActivity(act: ActivityType) {
    const curr = form.activity_preferences;
    set("activity_preferences", curr.includes(act) ? curr.filter((a) => a !== act) : [...curr, act]);
  }

  function goToStep(n: number) {
    setStep(n);
    trackEvent(EVENTS.ONBOARDING_STEP, { step: n });
  }

  async function handleFinish(location?: TrainingLocation) {
    setError(""); setLoading(true);
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

  const TOTAL = 5;

  if (step === 1) return (
    <Screen step={1} total={TOTAL}>
      <h2 className="wizard-title">Qual é o seu objetivo?</h2>
      <p className="wizard-sub">Isso define seu plano de treino personalizado.</p>
      <div className="opts">
        {GOALS.map((g) => (
          <OptionCard
            key={g.value}
            icon={g.icon}
            label={g.label}
            description={g.desc}
            selected={form.goal === g.value}
            onClick={() => { set("goal", g.value); goToStep(2); }}
          />
        ))}
      </div>
    </Screen>
  );

  if (step === 2) return (
    <Screen step={2} total={TOTAL}>
      <BackBtn onClick={() => goToStep(1)} />
      <h2 className="wizard-title">Seu nível de condicionamento?</h2>
      <p className="wizard-sub">Seja honesto — isso ajusta a intensidade.</p>
      <div className="opts">
        {LEVELS.map((l) => (
          <OptionCard
            key={l.value}
            icon={l.icon}
            label={l.label}
            description={l.desc}
            selected={form.fitness_level === l.value}
            onClick={() => { set("fitness_level", l.value); goToStep(3); }}
          />
        ))}
      </div>
    </Screen>
  );

  if (step === 3) return (
    <Screen step={3} total={TOTAL}>
      <BackBtn onClick={() => goToStep(2)} />
      <h2 className="wizard-title">Seus dados físicos</h2>
      <p className="wizard-sub">Usados para personalizar sua experiência.</p>

      {/* Gender segmented */}
      <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 24 }}>
        <span style={{ fontSize: 14, color: "var(--text-muted)", fontWeight: 600 }}>Como você se identifica?</span>
        <div className="segmented">
          {GENDERS.map((g) => (
            <button
              key={g.value}
              className={form.gender === g.value ? "sel" : ""}
              onClick={() => set("gender", g.value)}
            >
              {g.label}
            </button>
          ))}
        </div>
      </div>

      {/* Sliders */}
      {(["age", "weight_kg", "height_cm"] as const).map((key) => {
        const meta = {
          age:       { label: "Idade",  unit: "anos", min: 14,  max: 90  },
          weight_kg: { label: "Peso",   unit: "kg",   min: 35,  max: 180 },
          height_cm: { label: "Altura", unit: "cm",   min: 120, max: 220 },
        }[key];
        const value = Number(form[key]);
        return (
          <div key={key} className="slide-row">
            <div className="lab">
              <span>{meta.label}</span>
              <b>{value}<em>{meta.unit}</em></b>
            </div>
            <input
              type="range"
              min={meta.min}
              max={meta.max}
              step={1}
              value={form[key]}
              onChange={(e) => set(key, e.target.value)}
            />
            <div className="ends">
              <span>{meta.min} {meta.unit}</span>
              <span>{meta.max} {meta.unit}</span>
            </div>
          </div>
        );
      })}

      <button
        onClick={() => goToStep(4)}
        disabled={!form.gender}
        className="wizard-cta"
        style={{ marginTop: 32 }}
      >
        Continuar →
      </button>
    </Screen>
  );

  if (step === 4) return (
    <Screen step={4} total={TOTAL}>
      <BackBtn onClick={() => goToStep(3)} />
      <h2 className="wizard-title">O que você gosta de fazer?</h2>
      <p className="wizard-sub">Selecione pelo menos uma atividade.</p>

      <div className="opt-grid">
        {ACTIVITIES.map((a) => {
          const sel = form.activity_preferences.includes(a.value);
          return (
            <button
              key={a.value}
              className={`opt${sel ? " sel" : ""}`}
              onClick={() => toggleActivity(a.value)}
              style={{ flexDirection: "column", alignItems: "flex-start", gap: 8, padding: 14, position: "relative" }}
            >
              <span className="oicon" style={{ width: 36, height: 36, fontSize: 18 }}>{a.icon}</span>
              <span className="otxt"><b style={{ fontSize: 14 }}>{a.label}</b></span>
              <span className="chk" style={{ position: "absolute", top: 10, right: 10, width: 20, height: 20 }}>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round">
                  <path d="M20 6L9 17l-5-5" />
                </svg>
              </span>
            </button>
          );
        })}
      </div>

      <button
        onClick={() => { if (form.activity_preferences.length > 0) goToStep(5); }}
        disabled={form.activity_preferences.length === 0}
        className="wizard-cta"
        style={{ marginTop: 24 }}
      >
        Continuar →
      </button>
    </Screen>
  );

  // Step 5 — location
  return (
    <Screen step={5} total={TOTAL}>
      <BackBtn onClick={() => goToStep(4)} />
      <h2 className="wizard-title">Onde você costuma treinar?</h2>
      <p className="wizard-sub">Isso adapta os exercícios do seu plano.</p>

      {error && (
        <div style={{ background: "var(--hot-soft)", border: "1px solid oklch(0.70 0.19 28 / .35)", borderRadius: "var(--r-md)", padding: "12px 16px", fontSize: 14, color: "var(--hot)", marginBottom: 16 }}>
          {error}
        </div>
      )}

      <div className="opts">
        {LOCATIONS.map((l) => (
          <OptionCard
            key={l.value}
            icon={l.icon}
            label={l.label}
            description={l.desc}
            selected={form.training_location === l.value}
            onClick={() => { if (!loading) { set("training_location", l.value); handleFinish(l.value); }}}
          />
        ))}
      </div>

      {loading && (
        <div style={{ textAlign: "center", marginTop: 24, color: "var(--text-muted)", fontSize: 14 }}>
          Criando seu plano... ✨
        </div>
      )}
    </Screen>
  );
}
