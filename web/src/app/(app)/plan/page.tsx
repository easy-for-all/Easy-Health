"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ApiError, api } from "@/shared/lib/api";
import { LoadingScreen } from "@/shared/components/loading-screen";
import type { WorkoutPlan, WorkoutDayExercise } from "@/shared/types/workout";
import type { HealthProfile } from "@/shared/types/health-profile";
import { SwapModal } from "../workout/today/swap-modal";

function resolveImageSrc(src: string): string {
  return src;
}

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

type TrainingLocation = "gym" | "home" | "outdoor" | "any";

type Phase =
  | "loading" | "view"
  | "wizard_profile" | "wizard_days" | "wizard_location" | "wizard_modality"
  | "wizard_split"   | "wizard_cardio_type" | "wizard_cardio_format"
  | "wizard_custom"  | "wizard_generating";

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

export default function PlanPage() {
  const router = useRouter();
  const [phase, setPhase]          = useState<Phase>("loading");
  const [plan, setPlan]            = useState<WorkoutPlan | null>(null);
  const [allPlans, setAllPlans]    = useState<PlanSummary[]>([]);
  const [showHistory, setShowHistory] = useState(false);
  const [profile, setProfile]      = useState<HealthProfile | null>(null);
  const [error, setError]          = useState("");
  const [selectedDayId, setSelectedDayId] = useState<number | null>(null);
  const [genStep, setGenStep]   = useState(0);
  const genStepRef              = useRef(0);

  // Wizard state
  const [daysPerWeek, setDaysPerWeek] = useState(3);
  const [modality,    setModality]    = useState<Modality>("musculacao");
  const [splitType,   setSplitType]   = useState<SplitType>("ai_choice");
  const [cardioType,  setCardioType]  = useState<CardioType>("corrida");
  const [cardioFormat, setCardioFormat] = useState<CardioFormat>("ai_choice");
  const [customSplits, setCustomSplits] = useState<{ name: string; muscle_groups: string[] }[]>([]);
  const [trainingLocation, setTrainingLocation] = useState<TrainingLocation>("gym");

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

  async function handleDuplicateDay(dayId: number) {
    try {
      const { day: newDay } = await api.post<{ day: import("@/shared/types/workout").WorkoutDay }>(
        `/api/v1/workout_days/${dayId}/duplicate`,
        {}
      );
      if (plan) {
        setPlan({
          ...plan,
          days: [...plan.days, { ...newDay, exercise_count: newDay.exercises?.length ?? 0 }],
        });
      }
      setSelectedDayId(newDay.id);
    } catch {
      setError("Erro ao duplicar treino.");
    }
  }

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
    if (cType)   body.cardio_type      = cType;
    if (cFormat) body.cardio_format    = cFormat;
    if (cSplits) body.custom_splits    = cSplits;
    body.training_location = trainingLocation;
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
    "wizard_profile", "wizard_days", "wizard_location", "wizard_modality",
    "wizard_split", "wizard_cardio_type", "wizard_cardio_format", "wizard_custom",
  ];
  const wizardStep = WIZARD_ORDERED.indexOf(phase);
  const showProgress = wizardStep >= 0 && phase !== "wizard_generating";

  return (
    <div className="min-h-screen px-4 py-6">
      <header className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-900">Planejamento de Treinos</h1>
        {phase === "view" && (
          <button
            onClick={() => router.push("/dashboard")}
            className="flex items-center gap-1.5 rounded-full bg-primary-50 px-3 py-1.5 text-xs font-semibold text-primary-600 hover:bg-primary-100"
          >
            ✨ Dicas IA
          </button>
        )}
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
          <PlanView plan={plan} onDayClick={setSelectedDayId} onDuplicate={handleDuplicateDay} />
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
          onNext={() => setPhase("wizard_location")}
          onBack={() => setPhase(profile ? "wizard_profile" : "view")}
        />
      )}

      {phase === "wizard_location" && (
        <WizardLocation
          selected={trainingLocation}
          onSelect={setTrainingLocation}
          onNext={() => setPhase("wizard_modality")}
          onBack={() => setPhase("wizard_days")}
        />
      )}

      {phase === "wizard_modality" && (
        <WizardModality
          onSelect={afterModality}
          onBack={() => setPhase("wizard_location")}
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

      {selectedDayId != null && (
        <PlanDayDetailDrawer
          dayId={selectedDayId}
          onClose={() => setSelectedDayId(null)}
          onChanged={(updatedDay) => {
            if (!plan) return;
            setPlan({
              ...plan,
              days: plan.days.map((d) => (d.id === updatedDay.id ? { ...d, exercise_count: updatedDay.exercises?.length ?? d.exercise_count } : d)),
            });
          }}
        />
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

function PlanView({
  plan,
  onDayClick,
  onDuplicate,
}: {
  plan: WorkoutPlan;
  onDayClick: (dayId: number) => void;
  onDuplicate?: (dayId: number) => void;
}) {
  return (
    <div className="space-y-3">
      {plan.days?.map((day, idx) => (
        <div
          key={day.id}
          className="rounded-xl border border-gray-100 bg-white transition hover:border-primary-200 hover:bg-primary-50"
        >
          <button
            onClick={() => onDayClick(day.id)}
            className="w-full p-4 text-left"
          >
            <div className="flex items-center justify-between">
              <div>
                <p className="text-xs font-semibold text-gray-400">Treino {LETTERS[idx] ?? idx + 1}</p>
                <p className="font-semibold text-gray-900">{day.name}</p>
                <p className="mt-0.5 text-xs text-gray-400">
                  {day.exercise_count} exercícios
                  {day.muscle_groups?.length ? ` · ${day.muscle_groups.join(", ")}` : ""}
                </p>
              </div>
              <span className="text-gray-300 text-lg">›</span>
            </div>
          </button>
          {onDuplicate && (
            <div className="border-t border-gray-50 px-4 pb-3 pt-2">
              <button
                onClick={() => onDuplicate(day.id)}
                className="text-xs font-medium text-gray-400 hover:text-primary-600"
              >
                + Duplicar treino
              </button>
            </div>
          )}
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

const LOCATION_OPTIONS: { value: TrainingLocation; label: string; description: string; icon: string }[] = [
  { value: "gym",     label: "Academia",       description: "Aparelhos, barras e halteres",    icon: "🏋️" },
  { value: "home",    label: "Em casa",        description: "Peso corporal, sem equipamentos", icon: "🏠" },
  { value: "outdoor", label: "Ao ar livre",    description: "Parques, ruas e quadras",         icon: "🌳" },
  { value: "any",     label: "Varia",          description: "Depende do dia",                  icon: "🔄" },
];

function WizardLocation({
  selected, onSelect, onNext, onBack,
}: { selected: TrainingLocation; onSelect: (v: TrainingLocation) => void; onNext: () => void; onBack: () => void }) {
  return (
    <div>
      <button onClick={onBack} className="mb-4 text-sm text-gray-500 hover:text-gray-700">← Voltar</button>
      <h2 className="mb-2 text-lg font-bold text-gray-900">Onde você vai treinar?</h2>
      <p className="mb-6 text-sm text-gray-500">Isso adapta os exercícios disponíveis no seu plano.</p>
      <div className="space-y-3">
        {LOCATION_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            onClick={() => onSelect(opt.value)}
            className={`w-full rounded-2xl border-2 p-4 text-left transition ${
              selected === opt.value
                ? "border-primary-500 bg-primary-50 shadow-sm"
                : "border-gray-200 bg-white hover:border-primary-200 hover:bg-gray-50"
            }`}
          >
            <div className="flex items-start gap-3">
              <span className="text-2xl leading-none">{opt.icon}</span>
              <div>
                <p className="font-semibold text-gray-900">{opt.label}</p>
                <p className="mt-0.5 text-xs text-gray-500">{opt.description}</p>
              </div>
            </div>
          </button>
        ))}
      </div>
      <button onClick={onNext} className="mt-8 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white hover:bg-primary-600">
        Continuar →
      </button>
    </div>
  );
}

// ── Plan Day Detail Drawer ────────────────────────────────────────────────────

const CARDIO_EXERCISE_TYPES = ["cardio", "corrida", "caminhada", "hiit", "natacao"] as const;
function isCardioEx(ex: { exercise_type: string }) {
  return CARDIO_EXERCISE_TYPES.includes(ex.exercise_type as (typeof CARDIO_EXERCISE_TYPES)[number]);
}

const INTENSITIES = [
  { value: "leve", label: "Leve", color: "text-green-700 bg-green-50" },
  { value: "moderado", label: "Moderado", color: "text-yellow-700 bg-yellow-50" },
  { value: "intenso", label: "Intenso", color: "text-red-700 bg-red-50" },
] as const;

type ExerciseEdits = Record<number, { sets?: number; reps?: number; duration_minutes?: number; intensity?: string }>;

type AddExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  image_url: string;
};

type CardioAddConfig = { exerciseId: number; duration: number; intensity: string };

function PlanDayDetailDrawer({
  dayId,
  onClose,
  onChanged,
}: {
  dayId: number;
  onClose: () => void;
  onChanged: (day: import("@/shared/types/workout").WorkoutDay) => void;
}) {
  const [day, setDay] = useState<import("@/shared/types/workout").WorkoutDay | null>(null);
  const [exercises, setExercises] = useState<WorkoutDayExercise[]>([]);
  const [edits, setEdits] = useState<ExerciseEdits>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [drawerError, setDrawerError] = useState("");
  const [swapTarget, setSwapTarget] = useState<WorkoutDayExercise | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [addSearch, setAddSearch] = useState("");
  const [addResults, setAddResults] = useState<AddExerciseOption[]>([]);
  const [addLoading, setAddLoading] = useState(false);
  const [addTypeFilter, setAddTypeFilter] = useState<"all" | "cardio">("all");
  const [cardioConfig, setCardioConfig] = useState<CardioAddConfig | null>(null);
  const addTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    api.get<{ day: import("@/shared/types/workout").WorkoutDay }>(`/api/v1/workout_days/${dayId}`)
      .then(({ day: d }) => {
        setDay(d);
        setExercises(d.exercises ?? []);
      })
      .catch(() => setDrawerError("Erro ao carregar exercícios."))
      .finally(() => setLoading(false));
  }, [dayId]);

  const fetchAddOptions = useCallback(async (name: string, typeFilter: "all" | "cardio" = "all") => {
    setAddLoading(true);
    try {
      const params = new URLSearchParams({ name, exclude_ids: exercises.map((e) => e.exercise_id).join(",") });
      if (typeFilter === "cardio") params.set("exercise_types", CARDIO_EXERCISE_TYPES.join(","));
      const data = await api.get<AddExerciseOption[]>(`/api/v1/exercises?${params}`);
      const filtered = typeFilter === "cardio"
        ? data.filter((e) => isCardioEx(e))
        : data;
      setAddResults(filtered);
    } catch {
      setAddResults([]);
    } finally {
      setAddLoading(false);
    }
  }, [exercises]);

  function handleAddSearchChange(value: string) {
    setAddSearch(value);
    if (addTimerRef.current) clearTimeout(addTimerRef.current);
    addTimerRef.current = setTimeout(() => fetchAddOptions(value, addTypeFilter), 300);
  }

  function openAdd() {
    setAddSearch("");
    setAddResults([]);
    setAddTypeFilter("all");
    setCardioConfig(null);
    setShowAdd(true);
    fetchAddOptions("");
  }

  function handleAddTypeFilter(type: "all" | "cardio") {
    setAddTypeFilter(type);
    fetchAddOptions(addSearch, type);
  }

  function setField(id: number, field: "sets" | "reps", raw: string) {
    const value = Math.max(1, parseInt(raw, 10) || 1);
    setEdits((prev) => ({ ...prev, [id]: { ...prev[id], [field]: value } }));
  }

  function currentValue(ex: WorkoutDayExercise, field: "sets" | "reps"): number {
    return edits[ex.workout_day_exercise_id]?.[field] ?? ex[field];
  }

  async function handleDelete(id: number) {
    setDrawerError("");
    try {
      await api.delete(`/api/v1/workout_day_exercises/${id}`);
      const updated = exercises.filter((e) => e.workout_day_exercise_id !== id);
      setExercises(updated);
      if (day) onChanged({ ...day, exercises: updated });
    } catch (e: unknown) {
      setDrawerError(e instanceof Error ? e.message : "Erro ao excluir exercício.");
    }
  }

  async function handleSwap(wdeId: number, replacementId: number) {
    const updated = await api.post<WorkoutDayExercise>(
      `/api/v1/workout_day_exercises/${wdeId}/swap`,
      { replacement_exercise_id: replacementId }
    );
    const newList = exercises.map((e) => e.workout_day_exercise_id === wdeId ? updated : e);
    setExercises(newList);
    setSwapTarget(null);
    if (day) onChanged({ ...day, exercises: newList });
  }

  async function handleAdd(exerciseId: number, cardioParams?: { duration_minutes: number; intensity: string }) {
    if (!day) return;
    setDrawerError("");
    try {
      const body: Record<string, unknown> = { exercise_id: exerciseId };
      if (cardioParams) {
        body.duration_minutes = cardioParams.duration_minutes;
        body.intensity = cardioParams.intensity;
      }
      const created = await api.post<WorkoutDayExercise>(
        `/api/v1/workout_days/${day.id}/exercises`,
        body
      );
      const newList = [...exercises, created];
      setExercises(newList);
      setShowAdd(false);
      setCardioConfig(null);
      if (day) onChanged({ ...day, exercises: newList });
    } catch (e: unknown) {
      setDrawerError(e instanceof Error ? e.message : "Erro ao adicionar exercício.");
    }
  }

  async function handleMove(id: number, direction: "up" | "down") {
    if (!day) return;
    const idx = exercises.findIndex((e) => e.workout_day_exercise_id === id);
    if (idx === -1) return;
    if (direction === "up" && idx === 0) return;
    if (direction === "down" && idx === exercises.length - 1) return;
    const newList = [...exercises];
    const swapIdx = direction === "up" ? idx - 1 : idx + 1;
    [newList[idx], newList[swapIdx]] = [newList[swapIdx], newList[idx]];
    setExercises(newList);
    try {
      await api.patch(`/api/v1/workout_days/${day.id}/exercises/reorder`, {
        ordered_ids: newList.map((e) => e.workout_day_exercise_id),
      });
    } catch {
      setExercises(exercises);
    }
  }

  async function handleSave() {
    setSaving(true);
    setDrawerError("");
    try {
      await Promise.all(
        Object.entries(edits).map(([id, vals]) => {
          const ex = exercises.find((e) => e.workout_day_exercise_id === Number(id));
          if (!ex) return Promise.resolve();
          if (isCardioEx(ex)) {
            return api.patch(`/api/v1/workout_day_exercises/${id}`, {
              duration_minutes: vals.duration_minutes ?? ex.duration_minutes,
              intensity: vals.intensity ?? ex.intensity,
            });
          }
          return api.patch(`/api/v1/workout_day_exercises/${id}`, {
            sets: vals.sets ?? ex.sets,
            reps: vals.reps ?? ex.reps,
          });
        })
      );
      setEdits({});
      if (day) onChanged(day);
      onClose();
    } catch {
      setDrawerError("Erro ao salvar. Tente novamente.");
    } finally {
      setSaving(false);
    }
  }

  const hasDirty = Object.keys(edits).length > 0;

  return (
    <>
      <div className="fixed inset-0 z-50 flex items-end bg-black/50" onClick={onClose}>
        <div
          className="max-h-[90vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-8 pt-4"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
          <div className="flex items-center justify-between mt-2 mb-4">
            <h3 className="text-base font-bold text-gray-900">{day?.name ?? "Treino"}</h3>
            <button onClick={onClose} className="text-sm text-gray-400 hover:text-gray-600">Fechar</button>
          </div>

          {loading && <p className="py-8 text-center text-sm text-gray-400">Carregando...</p>}

          {!loading && drawerError && (
            <p className="mb-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{drawerError}</p>
          )}

          {!loading && exercises.length === 0 && !drawerError && (
            <p className="py-8 text-center text-sm text-gray-400">Nenhum exercício neste treino.</p>
          )}

          <div className="space-y-3">
            {exercises.map((ex) => (
              <div key={ex.workout_day_exercise_id} className="rounded-xl border border-gray-100 bg-white p-3">
                <div className="flex gap-3 mb-3">
                  {/* Exercise image */}
                  <img
                    src={resolveImageSrc(ex.image_url)}
                    alt={ex.name}
                    className="h-16 w-20 rounded-lg object-cover flex-shrink-0"
                    onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = `/exercise-images/${ex.exercise_type || "treino"}.svg`; }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-gray-900 text-sm leading-tight">{ex.name}</p>
                    {isCardioEx(ex) ? (
                      <p className="text-xs text-gray-400 mt-0.5">
                        {edits[ex.workout_day_exercise_id]?.duration_minutes ?? ex.duration_minutes ?? 20} min
                        {" · "}
                        <span className={`capitalize ${INTENSITIES.find(i => i.value === (edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity))?.color ?? "text-gray-400"}`}>
                          {INTENSITIES.find(i => i.value === (edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity))?.label ?? "Moderado"}
                        </span>
                      </p>
                    ) : (
                      <p className="text-xs text-gray-400 mt-0.5">
                        {currentValue(ex, "sets")} séries · {currentValue(ex, "reps")} reps
                      </p>
                    )}
                    <div className="flex gap-3 mt-2">
                      <button
                        onClick={() => setSwapTarget(ex)}
                        className="text-xs font-medium text-primary-500 hover:text-primary-700"
                      >
                        Trocar
                      </button>
                      <button
                        onClick={() => handleDelete(ex.workout_day_exercise_id)}
                        className="text-xs font-medium text-red-400 hover:text-red-600"
                      >
                        Excluir
                      </button>
                    </div>
                  </div>
                  <div className="flex flex-col gap-1 justify-center">
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "up")}
                      disabled={exercises.indexOf(ex) === 0}
                      className="flex h-7 w-7 items-center justify-center rounded-lg border border-gray-200 text-xs text-gray-400 disabled:opacity-25 hover:bg-gray-50"
                    >↑</button>
                    <button
                      onClick={() => handleMove(ex.workout_day_exercise_id, "down")}
                      disabled={exercises.indexOf(ex) === exercises.length - 1}
                      className="flex h-7 w-7 items-center justify-center rounded-lg border border-gray-200 text-xs text-gray-400 disabled:opacity-25 hover:bg-gray-50"
                    >↓</button>
                  </div>
                </div>

                {/* Editable fields: sets/reps for strength, duration/intensity for cardio */}
                {isCardioEx(ex) ? (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Duração (min)</label>
                      <input
                        type="number"
                        min={1}
                        max={120}
                        value={edits[ex.workout_day_exercise_id]?.duration_minutes ?? ex.duration_minutes ?? 20}
                        onChange={(e) => setEdits((prev) => ({
                          ...prev,
                          [ex.workout_day_exercise_id]: {
                            ...prev[ex.workout_day_exercise_id],
                            duration_minutes: Math.max(1, parseInt(e.target.value, 10) || 1),
                          },
                        }))}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Intensidade</label>
                      <select
                        value={edits[ex.workout_day_exercise_id]?.intensity ?? ex.intensity ?? "moderado"}
                        onChange={(e) => setEdits((prev) => ({
                          ...prev,
                          [ex.workout_day_exercise_id]: {
                            ...prev[ex.workout_day_exercise_id],
                            intensity: e.target.value,
                          },
                        }))}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      >
                        {INTENSITIES.map((i) => <option key={i.value} value={i.value}>{i.label}</option>)}
                      </select>
                    </div>
                  </div>
                ) : (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Séries</label>
                      <input
                        type="number"
                        min={1}
                        max={10}
                        value={currentValue(ex, "sets")}
                        onChange={(e) => setField(ex.workout_day_exercise_id, "sets", e.target.value)}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-400 mb-1">Reps</label>
                      <input
                        type="number"
                        min={1}
                        max={100}
                        value={currentValue(ex, "reps")}
                        onChange={(e) => setField(ex.workout_day_exercise_id, "reps", e.target.value)}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>

          {!loading && (
            <button
              onClick={openAdd}
              className="mt-4 w-full rounded-xl border border-dashed border-primary-300 py-3 text-sm font-semibold text-primary-600 hover:bg-primary-50"
            >
              + Adicionar exercício
            </button>
          )}

          {!loading && exercises.length > 0 && (
            <button
              onClick={handleSave}
              disabled={saving || !hasDirty}
              className="mt-3 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-50 hover:bg-primary-600"
            >
              {saving ? "Salvando..." : "Salvar alterações"}
            </button>
          )}
        </div>
      </div>

      {/* Swap modal */}
      {swapTarget && (
        <SwapModal
          exercise={swapTarget}
          onSwap={handleSwap}
          onClose={() => setSwapTarget(null)}
        />
      )}

      {/* Add exercise sheet */}
      {showAdd && (
        <div
          className="fixed inset-0 z-[60] flex items-end bg-black/40"
          onClick={() => { setShowAdd(false); setAddSearch(""); setCardioConfig(null); }}
        >
          <div
            className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
            <h3 className="mb-3 mt-2 text-base font-bold text-gray-900">Adicionar exercício</h3>

            {/* Type filter chips */}
            <div className="mb-3 flex gap-2">
              <button
                onClick={() => handleAddTypeFilter("all")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${addTypeFilter === "all" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600"}`}
              >
                Todos
              </button>
              <button
                onClick={() => handleAddTypeFilter("cardio")}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${addTypeFilter === "cardio" ? "bg-orange-500 text-white" : "bg-gray-100 text-gray-600"}`}
              >
                🏃 Cardio
              </button>
            </div>

            <input
              type="text"
              placeholder="Buscar por nome..."
              value={addSearch}
              onChange={(e) => handleAddSearchChange(e.target.value)}
              className="mb-3 w-full rounded-xl border border-gray-200 px-4 py-2.5 text-sm focus:border-primary-500 focus:outline-none"
            />

            {/* Cardio config step */}
            {cardioConfig && (
              <div className="mb-4 rounded-xl border border-orange-200 bg-orange-50 p-4">
                <p className="mb-3 text-sm font-semibold text-orange-800">Configurar cardio</p>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Duração (min)</label>
                    <input
                      type="number"
                      min={1}
                      max={120}
                      value={cardioConfig.duration}
                      onChange={(e) => setCardioConfig((p) => p ? { ...p, duration: Math.max(1, parseInt(e.target.value, 10) || 1) } : p)}
                      className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-center text-sm font-semibold focus:border-orange-400 focus:outline-none"
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Intensidade</label>
                    <select
                      value={cardioConfig.intensity}
                      onChange={(e) => setCardioConfig((p) => p ? { ...p, intensity: e.target.value } : p)}
                      className="w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm font-semibold focus:border-orange-400 focus:outline-none"
                    >
                      {INTENSITIES.map((i) => <option key={i.value} value={i.value}>{i.label}</option>)}
                    </select>
                  </div>
                </div>
                <div className="mt-3 flex gap-2">
                  <button
                    onClick={() => handleAdd(cardioConfig.exerciseId, { duration_minutes: cardioConfig.duration, intensity: cardioConfig.intensity })}
                    className="flex-1 rounded-lg bg-orange-500 py-2 text-sm font-semibold text-white hover:bg-orange-600"
                  >
                    Adicionar
                  </button>
                  <button
                    onClick={() => setCardioConfig(null)}
                    className="rounded-lg border border-gray-200 px-4 py-2 text-sm text-gray-500"
                  >
                    Cancelar
                  </button>
                </div>
              </div>
            )}

            {addLoading ? (
              <p className="rounded-lg bg-gray-50 p-3 text-center text-sm text-gray-400">Buscando...</p>
            ) : addResults.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhum exercício encontrado.</p>
            ) : (
              addResults.map((opt) => (
                <button
                  key={opt.id}
                  onClick={() => {
                    if (isCardioEx(opt)) {
                      setCardioConfig({ exerciseId: opt.id, duration: 20, intensity: "moderado" });
                    } else {
                      handleAdd(opt.id);
                    }
                  }}
                  className="mb-2 flex w-full gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50"
                >
                  <img
                    src={resolveImageSrc(opt.image_url)}
                    alt={opt.name}
                    className="h-12 w-16 rounded-md object-cover flex-shrink-0"
                    onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = `/exercise-images/${opt.exercise_type || "treino"}.svg`; }}
                  />
                  <div className="flex-1">
                    <p className="font-medium text-gray-900">{opt.name}</p>
                    <p className="text-xs text-gray-400">{opt.muscle_group ?? opt.exercise_type}</p>
                  </div>
                  {isCardioEx(opt) && (
                    <span className="self-center rounded-full bg-orange-100 px-2 py-0.5 text-xs font-semibold text-orange-700">Cardio</span>
                  )}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </>
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
