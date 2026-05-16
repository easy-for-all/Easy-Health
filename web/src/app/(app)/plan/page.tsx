"use client";

import { useEffect, useRef, useState } from "react";
import { ApiError, api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutPlan } from "@/shared/types/workout";
import type { HealthProfile } from "@/shared/types/health-profile";

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
  "Definindo a divisão semanal",
  "Selecionando exercícios",
  "Ajustando intensidade",
  "Configurando descanso",
  "Finalizando planejamento",
];

type PlanSummary = {
  id: number;
  active: boolean;
  created_at: string;
  days_count: number;
  days: { id: number; name: string; exercise_count: number }[];
};

type Modality  = "musculacao" | "cardio" | "misto" | "funcional" | "ai_choice";
type SplitType = "ai_choice" | "full_body" | "upper_lower" | "ab" | "abc" | "ppl" | "custom";
type CardioType   = "corrida" | "caminhada" | "bicicleta" | "eliptico" | "escada" | "remo" | "hiit" | "natacao" | "ai_choice";
type CardioFormat = "continuo_leve" | "continuo_moderado" | "intervalado" | "hiit" | "progressivo" | "recuperacao" | "ai_choice";

type Phase =
  | "loading" | "view"
  | "wizard_profile" | "wizard_days" | "wizard_modality"
  | "wizard_split"   | "wizard_cardio_type" | "wizard_cardio_format"
  | "wizard_custom"  | "wizard_generating";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function PlanPage() {
  const [phase, setPhase]       = useState<Phase>("loading");
  const [plan, setPlan]         = useState<WorkoutPlan | null>(null);
  const [allPlans, setAllPlans] = useState<PlanSummary[]>([]);
  const [showHistory, setShowHistory] = useState(false);
  const [profile, setProfile]   = useState<HealthProfile | null>(null);
  const [error, setError]       = useState("");
  const [genStep, setGenStep]   = useState(0);
  const genStepRef              = useRef(0);

  // Wizard state
  const [daysPerWeek, setDaysPerWeek] = useState(3);
  const [modality,    setModality]    = useState<Modality>("musculacao");
  const [splitType,   setSplitType]   = useState<SplitType>("ai_choice");
  const [cardioType,  setCardioType]  = useState<CardioType>("corrida");
  const [cardioFormat, setCardioFormat] = useState<CardioFormat>("ai_choice");
  const [customSplits, setCustomSplits] = useState<{ name: string; muscle_groups: string[] }[]>([]);

  useEffect(() => {
    Promise.all([
      api.get<WorkoutPlan>("/api/v1/workout_plan").catch(() => null),
      api.get<HealthProfile>("/api/v1/health_profile").catch(() => null),
      api.get<PlanSummary[]>("/api/v1/workout_plans").catch(() => []),
    ]).then(([p, hp, plans]) => {
      setPlan(p);
      setProfile(hp);
      setAllPlans(plans ?? []);
      if (hp) {
        setDaysPerWeek(hp.training_days_per_week ?? 3);
      }
      setPhase(p ? "view" : hp ? "wizard_profile" : "wizard_days");
    });
  }, []);

  function startWizard() {
    setError("");
    setPhase(profile ? "wizard_profile" : "wizard_days");
  }

  function afterModality(m: Modality) {
    setModality(m);
    if (m === "ai_choice" || m === "funcional") {
      handleGenerate(m, "ai_choice", undefined, undefined);
      return;
    }
    if (m === "musculacao") { setPhase("wizard_split"); return; }
    if (m === "cardio")     { setPhase("wizard_cardio_type"); return; }
    if (m === "misto")      { setPhase("wizard_split"); return; }
  }

  function afterSplit(s: SplitType) {
    setSplitType(s);
    if (s === "custom") { setPhase("wizard_custom"); return; }
    if (modality === "misto") { setPhase("wizard_cardio_type"); return; }
    handleGenerate(modality, s, undefined, undefined);
  }

  function afterCardioType(ct: CardioType) {
    setCardioType(ct);
    setPhase("wizard_cardio_format");
  }

  function afterCardioFormat(cf: CardioFormat) {
    setCardioFormat(cf);
    handleGenerate(modality, splitType, cardioType, cf);
  }

  function afterCustomSplit(splits: { name: string; muscle_groups: string[] }[]) {
    setCustomSplits(splits);
    handleGenerate(modality, "custom", undefined, undefined, splits);
  }

  async function handleGenerate(
    mod: Modality,
    split: SplitType,
    cType: CardioType | undefined,
    cFormat: CardioFormat | undefined,
    cSplits?: { name: string; muscle_groups: string[] }[]
  ) {
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

    const body: Record<string, unknown> = {
      training_days_per_week: daysPerWeek,
      modality: mod,
      split_type: split,
    };
    if (cType)   body.cardio_type   = cType;
    if (cFormat) body.cardio_format = cFormat;
    if (cSplits) body.custom_splits = cSplits;
    if (mod === "funcional") body.activity_preferences = ["funcional"];
    if (mod === "ai_choice") delete body.split_type;

    try {
      const [newPlan] = await Promise.all([
        api.post<WorkoutPlan>("/api/v1/workout_plan/regenerate", body),
        new Promise<void>((resolve) => setTimeout(resolve, GENERATION_STEPS.length * STEP_MS)),
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
      setPhase("wizard_modality");
    }
  }

  if (phase === "loading") return <LoadingScreen />;

  const WIZARD_ORDERED: Phase[] = [
    "wizard_profile", "wizard_days", "wizard_modality",
    "wizard_split", "wizard_cardio_type", "wizard_cardio_format", "wizard_custom",
  ];
  const wizardStep = WIZARD_ORDERED.indexOf(phase);
  const showProgress = wizardStep >= 0 && phase !== "wizard_generating";

  return (
    <div className="min-h-screen px-4 py-6">
      <header className="mb-6">
        <h1 className="text-xl font-bold text-gray-900">Planejamento de Treinos</h1>
      </header>

      {showProgress && (
        <div className="mb-6 flex gap-1">
          {WIZARD_ORDERED.map((_, i) => (
            <div
              key={i}
              className={`h-1 flex-1 rounded-full transition-colors ${i <= wizardStep ? "bg-primary-500" : "bg-gray-200"}`}
            />
          ))}
        </div>
      )}

      {phase === "view" && plan && (
        <>
          <PlanView plan={plan} />
          <button onClick={startWizard} className="mt-6 w-full rounded-xl border border-gray-200 py-3 text-sm font-medium text-gray-600 hover:bg-gray-50">
            Replanejar
          </button>
          {allPlans.length > 1 && (
            <div className="mt-6">
              <button
                onClick={() => setShowHistory((v) => !v)}
                className="flex w-full items-center justify-between rounded-xl border border-gray-100 bg-white px-4 py-3"
              >
                <span className="text-sm font-semibold text-gray-700">Treinos anteriores</span>
                <span className="text-xs text-gray-400">{showHistory ? "▲ Ocultar" : "▼ Ver"}</span>
              </button>
              {showHistory && (
                <div className="mt-2 space-y-2">
                  {allPlans.filter((p) => !p.active).map((p) => (
                    <PlanHistoryCard key={p.id} plan={p} />
                  ))}
                </div>
              )}
            </div>
          )}
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
          onNext={() => setPhase("wizard_modality")}
          onBack={() => setPhase(profile ? "wizard_profile" : "view")}
        />
      )}

      {phase === "wizard_modality" && (
        <WizardModality
          onSelect={afterModality}
          onBack={() => setPhase("wizard_days")}
        />
      )}

      {phase === "wizard_split" && (
        <WizardSplitType
          onSelect={afterSplit}
          onBack={() => setPhase("wizard_modality")}
        />
      )}

      {phase === "wizard_cardio_type" && (
        <WizardCardioType
          onSelect={afterCardioType}
          onBack={() => modality === "misto" ? setPhase("wizard_split") : setPhase("wizard_modality")}
        />
      )}

      {phase === "wizard_cardio_format" && (
        <WizardCardioFormat
          cardioType={cardioType}
          onSelect={afterCardioFormat}
          onBack={() => setPhase("wizard_cardio_type")}
        />
      )}

      {phase === "wizard_custom" && (
        <WizardCustomSplit
          daysPerWeek={daysPerWeek}
          onConfirm={afterCustomSplit}
          onBack={() => setPhase("wizard_split")}
        />
      )}

      {phase === "wizard_generating" && <GeneratingView step={genStep} />}

      {error && phase === "wizard_modality" && (
        <p className="mt-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>
      )}
    </div>
  );
}

// ── Shared UI ────────────────────────────────────────────────────────────────

type CardOption<T> = { value: T; label: string; description: string; icon: string };

function SelectionCard<T extends string>({
  option, selected, onSelect,
}: { option: CardOption<T>; selected: boolean; onSelect: (v: T) => void }) {
  return (
    <button
      onClick={() => onSelect(option.value)}
      className={`w-full rounded-2xl border-2 p-4 text-left transition ${
        selected
          ? "border-primary-500 bg-primary-50 shadow-sm"
          : "border-gray-200 bg-white hover:border-primary-200 hover:bg-gray-50"
      }`}
    >
      <div className="flex items-start gap-3">
        <span className="text-2xl leading-none">{option.icon}</span>
        <div>
          <p className="font-semibold text-gray-900">{option.label}</p>
          <p className="mt-0.5 text-xs text-gray-500">{option.description}</p>
        </div>
        {selected && (
          <div className="ml-auto flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-primary-500">
            <span className="text-xs text-white">✓</span>
          </div>
        )}
      </div>
    </button>
  );
}

function WizardHeader({ title, subtitle, onBack }: { title: string; subtitle: string; onBack?: () => void }) {
  return (
    <>
      {onBack && (
        <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">
          ← Voltar
        </button>
      )}
      <h2 className="mb-1 text-lg font-bold text-gray-900">{title}</h2>
      <p className="mb-5 text-sm text-gray-500">{subtitle}</p>
    </>
  );
}

// ── Wizard steps ──────────────────────────────────────────────────────────────

const MODALITY_OPTIONS: CardOption<Modality>[] = [
  { value: "musculacao", label: "Musculação",     icon: "🏋️", description: "Treino com pesos, barras e máquinas." },
  { value: "cardio",     label: "Cardio",          icon: "❤️", description: "Corrida, bike, elíptico e mais." },
  { value: "misto",      label: "Musculação + Cardio", icon: "⚡", description: "Combinação de força e resistência." },
  { value: "funcional",  label: "Funcional",       icon: "🤸", description: "Kettlebell, TRX, corda e movimentos naturais." },
  { value: "ai_choice",  label: "IA Escolhe",      icon: "🤖", description: "Deixa a IA montar o melhor plano para você." },
];

function WizardModality({ onSelect, onBack }: { onSelect: (m: Modality) => void; onBack: () => void }) {
  const [selected, setSelected] = useState<Modality | null>(null);

  return (
    <div>
      <WizardHeader title="Qual modalidade?" subtitle="Escolha o tipo de treino que você quer focar." onBack={onBack} />
      <div className="space-y-3">
        {MODALITY_OPTIONS.map((opt) => (
          <SelectionCard
            key={opt.value}
            option={opt}
            selected={selected === opt.value}
            onSelect={(v) => { setSelected(v); setTimeout(() => onSelect(v), 200); }}
          />
        ))}
      </div>
    </div>
  );
}

const SPLIT_OPTIONS: CardOption<SplitType>[] = [
  { value: "ai_choice",   label: "IA Decide",              icon: "🤖", description: "A IA escolhe a melhor divisão para seu perfil." },
  { value: "full_body",   label: "Full Body",               icon: "💪", description: "Corpo todo em cada sessão." },
  { value: "upper_lower", label: "Superiores / Inferiores", icon: "⬆️", description: "Alterna entre parte superior e inferior." },
  { value: "ab",          label: "AB",                      icon: "🔄", description: "Dois treinos alternados (A e B)." },
  { value: "abc",         label: "ABC",                     icon: "🔤", description: "Três treinos em rotação (A, B e C)." },
  { value: "ppl",         label: "Push / Pull / Legs",      icon: "🏋️", description: "Empurrar, puxar e pernas separados." },
  { value: "custom",      label: "Personalizado",           icon: "✏️", description: "Monte suas próprias divisões musculares." },
];

function WizardSplitType({ onSelect, onBack }: { onSelect: (s: SplitType) => void; onBack: () => void }) {
  const [selected, setSelected] = useState<SplitType | null>(null);

  return (
    <div>
      <WizardHeader title="Como quer organizar?" subtitle="Escolha a divisão de musculação que prefere." onBack={onBack} />
      <div className="space-y-3">
        {SPLIT_OPTIONS.map((opt) => (
          <SelectionCard
            key={opt.value}
            option={opt}
            selected={selected === opt.value}
            onSelect={(v) => { setSelected(v); setTimeout(() => onSelect(v), 200); }}
          />
        ))}
      </div>
    </div>
  );
}

const CARDIO_TYPE_OPTIONS: CardOption<CardioType>[] = [
  { value: "corrida",    label: "Corrida",       icon: "🏃", description: "Esteira ou rua." },
  { value: "caminhada",  label: "Caminhada",     icon: "🚶", description: "Caminhada ativa ou em inclinação." },
  { value: "bicicleta",  label: "Bike",          icon: "🚲", description: "Bike estacionária ou ao ar livre." },
  { value: "eliptico",   label: "Elíptico",      icon: "🔁", description: "Baixo impacto, alta eficiência." },
  { value: "remo",       label: "Remo",          icon: "🚣", description: "Ergômetro ou remo funcional." },
  { value: "hiit",       label: "HIIT",          icon: "🔥", description: "Alta intensidade com intervalos." },
  { value: "natacao",    label: "Natação",        icon: "🏊", description: "Nado livre, borboleta e mais." },
  { value: "ai_choice",  label: "IA Escolhe",    icon: "🤖", description: "A IA decide o melhor cardio para você." },
];

function WizardCardioType({ onSelect, onBack }: { onSelect: (ct: CardioType) => void; onBack: () => void }) {
  const [selected, setSelected] = useState<CardioType | null>(null);

  return (
    <div>
      <WizardHeader title="Que tipo de cardio?" subtitle="Selecione a modalidade de cardio preferida." onBack={onBack} />
      <div className="space-y-3">
        {CARDIO_TYPE_OPTIONS.map((opt) => (
          <SelectionCard
            key={opt.value}
            option={opt}
            selected={selected === opt.value}
            onSelect={(v) => { setSelected(v); setTimeout(() => onSelect(v), 200); }}
          />
        ))}
      </div>
    </div>
  );
}

const CARDIO_FORMAT_OPTIONS: CardOption<CardioFormat>[] = [
  { value: "ai_choice",        label: "IA Decide",         icon: "🤖", description: "A IA escolhe o formato ideal." },
  { value: "continuo_leve",    label: "Contínuo Leve",     icon: "🌱", description: "Ritmo baixo, longa duração. Ótimo para recuperação." },
  { value: "continuo_moderado",label: "Contínuo Moderado", icon: "🎯", description: "Intensidade média sustentada. Queima de gordura eficiente." },
  { value: "intervalado",      label: "Intervalado",       icon: "🔄", description: "Alternância de esforço e descanso. Melhora condicionamento." },
  { value: "hiit",             label: "HIIT",              icon: "⚡", description: "Alta intensidade em blocos curtos. Máximo resultado em menos tempo." },
  { value: "progressivo",      label: "Progressivo",       icon: "📈", description: "Intensidade aumenta ao longo da sessão." },
  { value: "recuperacao",      label: "Recuperação",       icon: "🧘", description: "Ritmo suave para dias de recuperação ativa." },
];

function WizardCardioFormat({
  cardioType,
  onSelect,
  onBack,
}: { cardioType: CardioType; onSelect: (cf: CardioFormat) => void; onBack: () => void }) {
  const [selected, setSelected] = useState<CardioFormat | null>(null);
  const typeLabel = CARDIO_TYPE_OPTIONS.find((o) => o.value === cardioType)?.label ?? "Cardio";

  return (
    <div>
      <WizardHeader
        title="Como prefere fazer?"
        subtitle={`Escolha o formato para o treino de ${typeLabel}.`}
        onBack={onBack}
      />
      <div className="space-y-3">
        {CARDIO_FORMAT_OPTIONS.map((opt) => (
          <SelectionCard
            key={opt.value}
            option={opt}
            selected={selected === opt.value}
            onSelect={(v) => { setSelected(v); setTimeout(() => onSelect(v), 200); }}
          />
        ))}
      </div>
    </div>
  );
}

const ALL_MUSCLE_GROUPS = [
  { value: "chest",     label: "Peito" },
  { value: "back",      label: "Costas" },
  { value: "shoulders", label: "Ombros" },
  { value: "biceps",    label: "Bíceps" },
  { value: "triceps",   label: "Tríceps" },
  { value: "legs",      label: "Pernas" },
  { value: "core",      label: "Core" },
];

function WizardCustomSplit({
  daysPerWeek,
  onConfirm,
  onBack,
}: {
  daysPerWeek: number;
  onConfirm: (splits: { name: string; muscle_groups: string[] }[]) => void;
  onBack: () => void;
}) {
  const [splits, setSplits] = useState<{ name: string; muscle_groups: string[] }[]>([
    { name: "Treino A", muscle_groups: [] },
  ]);

  function addSplit() {
    if (splits.length >= daysPerWeek) return;
    setSplits((prev) => [...prev, { name: `Treino ${LETTERS[prev.length]}`, muscle_groups: [] }]);
  }

  function removeSplit(idx: number) {
    setSplits((prev) => prev.filter((_, i) => i !== idx));
  }

  function toggleMuscle(splitIdx: number, muscle: string) {
    setSplits((prev) =>
      prev.map((s, i) =>
        i !== splitIdx ? s : {
          ...s,
          muscle_groups: s.muscle_groups.includes(muscle)
            ? s.muscle_groups.filter((m) => m !== muscle)
            : [...s.muscle_groups, muscle],
        }
      )
    );
  }

  function updateName(splitIdx: number, name: string) {
    setSplits((prev) => prev.map((s, i) => (i === splitIdx ? { ...s, name } : s)));
  }

  const canConfirm = splits.length > 0 && splits.every((s) => s.muscle_groups.length > 0);

  return (
    <div>
      <WizardHeader
        title="Monte suas divisões"
        subtitle={`Defina até ${daysPerWeek} treinos com os grupos musculares de cada um.`}
        onBack={onBack}
      />

      <div className="space-y-4">
        {splits.map((split, idx) => (
          <div key={idx} className="rounded-2xl border border-gray-200 bg-white p-4">
            <div className="mb-3 flex items-center gap-2">
              <input
                type="text"
                value={split.name}
                onChange={(e) => updateName(idx, e.target.value)}
                className="flex-1 rounded-lg border border-gray-200 px-3 py-1.5 text-sm font-medium focus:border-primary-500 focus:outline-none"
              />
              {splits.length > 1 && (
                <button onClick={() => removeSplit(idx)} className="text-sm text-red-400 hover:text-red-600">
                  Remover
                </button>
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              {ALL_MUSCLE_GROUPS.map((mg) => (
                <button
                  key={mg.value}
                  onClick={() => toggleMuscle(idx, mg.value)}
                  className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                    split.muscle_groups.includes(mg.value)
                      ? "bg-primary-500 text-white"
                      : "bg-gray-100 text-gray-600 hover:bg-primary-100"
                  }`}
                >
                  {mg.label}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>

      {splits.length < daysPerWeek && (
        <button
          onClick={addSplit}
          className="mt-3 w-full rounded-xl border border-dashed border-primary-300 py-3 text-sm font-medium text-primary-500 hover:bg-primary-50"
        >
          + Adicionar treino
        </button>
      )}

      <button
        onClick={() => onConfirm(splits)}
        disabled={!canConfirm}
        className="mt-6 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-50 hover:bg-primary-600"
      >
        Gerar treino
      </button>
    </div>
  );
}

// ── Existing components ───────────────────────────────────────────────────────

function PlanView({ plan }: { plan: WorkoutPlan }) {
  return (
    <div className="space-y-3">
      {plan.days?.map((day, idx) => (
        <div key={day.id} className="rounded-xl border border-gray-100 bg-white p-4">
          <p className="text-xs font-semibold text-gray-400">Treino {LETTERS[idx] ?? idx + 1}</p>
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

function PlanHistoryCard({ plan }: { plan: PlanSummary }) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className="rounded-xl border border-gray-100 bg-white p-4">
      <button className="flex w-full items-center justify-between" onClick={() => setExpanded((v) => !v)}>
        <div className="text-left">
          <p className="text-sm font-semibold text-gray-700">
            {new Date(plan.created_at).toLocaleDateString("pt-BR", { day: "numeric", month: "short", year: "numeric" })}
          </p>
          <p className="text-xs text-gray-400">{plan.days_count} dias · {plan.days.reduce((s, d) => s + d.exercise_count, 0)} exercícios</p>
        </div>
        <span className="text-xs text-gray-400">{expanded ? "▲" : "▼"}</span>
      </button>
      {expanded && (
        <div className="mt-3 space-y-2 border-t border-gray-50 pt-3">
          {plan.days.map((d, i) => (
            <div key={d.id} className="flex items-center gap-2">
              <span className="flex h-6 w-6 items-center justify-center rounded-full bg-gray-100 text-xs font-bold text-gray-500">{LETTERS[i] ?? i + 1}</span>
              <p className="text-sm text-gray-700">{d.name}</p>
              <span className="ml-auto text-xs text-gray-400">{d.exercise_count} ex.</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function WizardProfile({
  profile, onNext, onCancel,
}: { profile: HealthProfile; onNext: () => void; onCancel?: () => void }) {
  return (
    <div>
      {onCancel && (
        <button onClick={onCancel} className="mb-4 text-sm text-gray-400 hover:text-gray-600">← Cancelar</button>
      )}
      <h2 className="mb-2 text-lg font-bold text-gray-900">Seu perfil de treino</h2>
      <p className="mb-4 text-sm text-gray-500">Vamos usar esses dados para montar seu planejamento.</p>
      <div className="rounded-2xl border border-gray-100 bg-white p-5 space-y-3">
        <ProfileRow label="Nível"    value={LEVEL_LABELS[profile.fitness_level]} />
        <ProfileRow label="Objetivo" value={GOAL_LABELS[profile.goal]} />
      </div>
      <button onClick={onNext} className="mt-6 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600">
        Continuar →
      </button>
    </div>
  );
}

function ProfileRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-sm text-gray-500">{label}</span>
      <span className="text-sm font-medium text-gray-900">{value}</span>
    </div>
  );
}

function WizardDays({
  selected, onSelect, onNext, onBack,
}: { selected: number; onSelect: (n: number) => void; onNext: () => void; onBack: () => void }) {
  return (
    <div>
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">← Voltar</button>
      <h2 className="mb-2 text-lg font-bold text-gray-900">Quantos dias por semana?</h2>
      <p className="mb-6 text-sm text-gray-500">Escolha com base na sua disponibilidade.</p>
      <div className="flex justify-center gap-3">
        {[2, 3, 4, 5, 6].map((n) => (
          <button
            key={n}
            onClick={() => onSelect(n)}
            className={`flex h-14 w-14 items-center justify-center rounded-full text-lg font-bold transition ${
              selected === n ? "bg-primary-500 text-white shadow-md" : "border-2 border-gray-200 text-gray-600 hover:border-primary-300"
            }`}
          >
            {n}
          </button>
        ))}
      </div>
      <p className="mt-3 text-center text-xs text-gray-400">dias por semana</p>
      <button onClick={onNext} className="mt-8 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600">
        Continuar →
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
            className={`flex items-center gap-3 transition-all duration-500 ${idx <= step ? "opacity-100 translate-x-0" : "opacity-20"}`}
          >
            <div className={`h-2 w-2 flex-shrink-0 rounded-full transition-colors ${
              idx < step ? "bg-primary-500" : idx === step ? "animate-pulse bg-primary-400" : "bg-gray-200"
            }`} />
            <p className={`text-sm font-medium ${
              idx < step ? "text-primary-700" : idx === step ? "text-gray-800" : "text-gray-400"
            }`}>
              {msg}{idx < step && " ✓"}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
