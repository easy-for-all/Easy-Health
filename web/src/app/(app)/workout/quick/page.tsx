"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { api } from "@/shared/lib/api";
import { AITrainerAvatar, AITrainerBubble } from "@/shared/components/ai-trainer";
import type { WorkoutDay } from "@/shared/types/workout";

type Duration = 15 | 30 | 45 | 60;
type Difficulty = "iniciante" | "moderado" | "intenso";
type Location = "academia" | "casa" | "ar_livre";
type MuscleGroup = "chest_back" | "legs" | "shoulders_arms" | "core" | "full_body";

const DURATION_OPTIONS: { value: Duration; label: string; sub: string }[] = [
  { value: 15, label: "15 min", sub: "Rápido" },
  { value: 30, label: "30 min", sub: "Padrão" },
  { value: 45, label: "45 min", sub: "Completo" },
  { value: 60, label: "60 min+", sub: "Intenso" },
];

const DIFFICULTY_OPTIONS: { value: Difficulty; label: string; emoji: string; sub: string }[] = [
  { value: "iniciante", label: "Iniciante", emoji: "🟢", sub: "Mais descanso, menos peso" },
  { value: "moderado",  label: "Moderado",  emoji: "🟡", sub: "Equilíbrio esforço/recuperação" },
  { value: "intenso",   label: "Intenso",   emoji: "🔴", sub: "Mais séries, menos descanso" },
];

const LOCATION_OPTIONS: { value: Location; label: string; emoji: string }[] = [
  { value: "academia",  label: "Academia",   emoji: "🏋️" },
  { value: "casa",      label: "Em casa",    emoji: "🏠" },
  { value: "ar_livre",  label: "Ao ar livre", emoji: "🌳" },
];

const MUSCLE_OPTIONS: { value: MuscleGroup; label: string; emoji: string; groups: string[] }[] = [
  { value: "full_body",      label: "Sem preferência", emoji: "💪", groups: [] },
  { value: "chest_back",     label: "Peito & Costas",  emoji: "🫀", groups: ["chest", "back"] },
  { value: "legs",           label: "Pernas",          emoji: "🦵", groups: ["legs"] },
  { value: "shoulders_arms", label: "Ombros & Braços", emoji: "💪", groups: ["shoulders", "biceps", "triceps"] },
  { value: "core",           label: "Core",            emoji: "🎯", groups: ["core"] },
];

const TRAINER_MESSAGES: Record<number, string> = {
  1: "Ótimo! Quanto tempo você tem hoje?",
  2: "Perfeito. Qual é o nível de intensidade?",
  3: "Onde você vai treinar?",
  4: "Alguma preferência muscular? (opcional)",
};

const STEP_TITLES = [
  "Quanto tempo?",
  "Qual intensidade?",
  "Onde vai treinar?",
  "Foco muscular",
];

export default function QuickWorkoutPage() {
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [duration, setDuration] = useState<Duration | null>(null);
  const [difficulty, setDifficulty] = useState<Difficulty | null>(null);
  const [location, setLocation] = useState<Location | null>(null);
  const [muscleGroup, setMuscleGroup] = useState<MuscleGroup | null>(null);
  const [generating, setGenerating] = useState(false);
  const [error, setError] = useState("");

  function next() {
    setStep((s) => s + 1);
  }

  async function generate(muscleGroupOverride?: MuscleGroup | null) {
    if (!duration || !difficulty || !location) return;
    setGenerating(true);
    setError("");

    const mg = muscleGroupOverride !== undefined ? muscleGroupOverride : muscleGroup;
    const chosen = MUSCLE_OPTIONS.find((m) => m.value === (mg ?? "full_body"));
    const muscle_groups = chosen?.groups ?? [];

    try {
      const data = await api.post<{ day: WorkoutDay }>("/api/v1/quick_workouts", {
        duration_minutes: duration,
        difficulty,
        location,
        muscle_groups,
      });
      sessionStorage.setItem("wk_quick_day", JSON.stringify(data.day));
      router.push("/workout/today?quick=1");
    } catch {
      setGenerating(false);
      setError("Não foi possível gerar o treino. Tente novamente.");
    }
  }

  if (generating) {
    return <GeneratingScreen difficulty={difficulty ?? "moderado"} />;
  }

  return (
    <div className="flex min-h-screen flex-col bg-[#0a0f1e] px-4 pt-6" style={{ paddingBottom: "var(--nav-pb)" }}>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <button onClick={() => (step > 1 ? setStep(step - 1) : router.back())} className="text-slate-400 text-sm">
          ← Voltar
        </button>
        <span className="text-xs font-medium text-slate-500">{step}/4</span>
      </div>

      {/* Progress */}
      <div className="mb-6 h-1 rounded-full bg-slate-800">
        <motion.div
          className="h-1 rounded-full bg-primary-500"
          animate={{ width: `${(step / 4) * 100}%` }}
          transition={{ duration: 0.3, ease: "easeOut" }}
        />
      </div>

      {/* AI Trainer */}
      <div className="flex items-start gap-3 mb-6">
        <AITrainerAvatar mood="speaking" size="sm" />
        <AITrainerBubble message={TRAINER_MESSAGES[step]} mood="speaking" show side="left" />
      </div>

      {/* Step title */}
      <h1 className="text-2xl font-bold text-white mb-5">{STEP_TITLES[step - 1]}</h1>

      {/* Step content */}
      <AnimatePresence mode="wait">
        <motion.div
          key={step}
          initial={{ opacity: 0, x: 24 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -24 }}
          transition={{ duration: 0.18, ease: "easeOut" }}
          className="flex-1"
        >
          {step === 1 && (
            <div className="grid grid-cols-2 gap-3">
              {DURATION_OPTIONS.map((opt) => (
                <SelectCard
                  key={opt.value}
                  selected={duration === opt.value}
                  onClick={() => { setDuration(opt.value); next(); }}
                  label={opt.label}
                  sub={opt.sub}
                  icon={null}
                />
              ))}
            </div>
          )}

          {step === 2 && (
            <div className="space-y-3">
              {DIFFICULTY_OPTIONS.map((opt) => (
                <SelectCard
                  key={opt.value}
                  selected={difficulty === opt.value}
                  onClick={() => { setDifficulty(opt.value); next(); }}
                  label={opt.label}
                  sub={opt.sub}
                  icon={opt.emoji}
                  horizontal
                />
              ))}
            </div>
          )}

          {step === 3 && (
            <div className="grid grid-cols-3 gap-3">
              {LOCATION_OPTIONS.map((opt) => (
                <SelectCard
                  key={opt.value}
                  selected={location === opt.value}
                  onClick={() => { setLocation(opt.value); next(); }}
                  label={opt.label}
                  icon={opt.emoji}
                />
              ))}
            </div>
          )}

          {step === 4 && (
            <div className="space-y-2.5">
              {MUSCLE_OPTIONS.map((opt) => (
                <SelectCard
                  key={opt.value}
                  selected={muscleGroup === opt.value || (opt.value === "full_body" && !muscleGroup)}
                  onClick={() => {
                    const mg = opt.value === "full_body" ? null : opt.value as MuscleGroup;
                    setMuscleGroup(mg);
                    generate(mg);
                  }}
                  label={opt.label}
                  icon={opt.emoji}
                  horizontal
                />
              ))}
            </div>
          )}
        </motion.div>
      </AnimatePresence>

      {/* Error feedback */}
      {error && (
        <div className="mt-auto pt-6">
          <p className="rounded-xl bg-red-500/15 px-4 py-3 text-sm text-red-400 text-center">
            {error}
          </p>
        </div>
      )}
    </div>
  );
}

function SelectCard({
  selected,
  onClick,
  label,
  sub,
  icon,
  horizontal = false,
}: {
  selected: boolean;
  onClick: () => void;
  label: string;
  sub?: string;
  icon?: string | null;
  horizontal?: boolean;
}) {
  return (
    <motion.button
      onClick={onClick}
      whileTap={{ scale: 0.96 }}
      className={`${horizontal ? "flex items-center gap-3 px-4 py-4" : "flex flex-col items-center justify-center py-5 px-3"} w-full rounded-2xl border-2 text-left transition-colors ${
        selected
          ? "border-primary-500 bg-primary-500/15 text-white"
          : "border-slate-700 bg-slate-900 text-slate-300"
      }`}
    >
      {icon && <span className={horizontal ? "text-2xl shrink-0" : "text-3xl mb-2"}>{icon}</span>}
      <div>
        <p className={`font-semibold ${horizontal ? "text-base" : "text-sm text-center"}`}>{label}</p>
        {sub && <p className="mt-0.5 text-xs text-slate-400 font-normal">{sub}</p>}
      </div>
      {selected && horizontal && <span className="ml-auto text-primary-400">✓</span>}
    </motion.button>
  );
}

function GeneratingScreen({ difficulty }: { difficulty: Difficulty }) {
  const msgs = [
    "Analisando seu perfil...",
    "Selecionando exercícios...",
    "Ajustando séries e cargas...",
    "Preparando seu treino...",
  ];

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-[#0a0f1e] px-6 text-center">
      <AITrainerAvatar mood="thinking" size="lg" />
      <p className="mt-4 text-lg font-bold text-white">Montando seu treino...</p>
      <div className="mt-6 space-y-2 w-full max-w-xs">
        {msgs.map((msg, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.4, duration: 0.3 }}
            className="flex items-center gap-2 rounded-xl bg-slate-900/60 px-4 py-2.5"
          >
            <motion.span
              animate={{ opacity: [0.4, 1, 0.4] }}
              transition={{ duration: 1.5, repeat: Infinity, delay: i * 0.2 }}
              className="text-primary-400 text-sm"
            >
              ◉
            </motion.span>
            <span className="text-sm text-slate-300">{msg}</span>
          </motion.div>
        ))}
      </div>
    </div>
  );
}
