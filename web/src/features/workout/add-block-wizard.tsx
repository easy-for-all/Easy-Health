"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useRef, useState } from "react";
import { api } from "@/shared/lib/api";
import { getGymSafeImageUrl } from "@/shared/utils/exercise-image";
import type { WorkoutDayExercise } from "@/shared/types/workout";
import { isValidBlockSize, minExercisesForBlockType, type WizardBlockType } from "@/features/workout/workout-blocks";

type ExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  image_url?: string | null;
  gif_url?: string | null;
};

type Step = "pick_exercises" | "configure";

type ExerciseConfig = { sets: number; reps: number };

export interface CreatedBlockResult {
  block_id: number;
  block_type: string;
  exercises: WorkoutDayExercise[];
}

/**
 * Wizard for manually creating a composite block (superset or circuit) from
 * scratch: pick 2+ (superset) or 3+ (circuit) exercises, then set rounds/
 * reps/sets, then POST /workout_days/:dayId/blocks in one shot. Deliberately
 * does not collect a "rest between exercises" field - the guided execution
 * (nextStepInBlock) never pauses between exercises within the same round,
 * only between rounds, so asking for it here would promise a behavior the
 * app doesn't deliver yet.
 */
export function AddBlockWizard({
  dayId,
  blockType,
  excludeExerciseIds,
  onCreated,
  onClose,
}: {
  dayId: number;
  blockType: WizardBlockType;
  excludeExerciseIds: number[];
  onCreated: (result: CreatedBlockResult) => void;
  onClose: () => void;
}) {
  const [step, setStep] = useState<Step>("pick_exercises");
  const [search, setSearch] = useState("");
  const [results, setResults] = useState<ExerciseOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<ExerciseOption[]>([]);
  const [rounds, setRounds] = useState(3);
  const [restBetweenRounds, setRestBetweenRounds] = useState(90);
  const [configs, setConfigs] = useState<Record<number, ExerciseConfig>>({});
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const searchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const minExercises = minExercisesForBlockType(blockType);
  const label = blockType === "superset" ? "Superset" : "Circuito";

  async function fetchOptions(name: string, currentSelected: ExerciseOption[]) {
    setLoading(true);
    try {
      const excludeIds = [...excludeExerciseIds, ...currentSelected.map((s) => s.id)].join(",");
      const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?name=${encodeURIComponent(name)}&exclude_ids=${excludeIds}`);
      setResults(data);
    } catch {
      setResults([]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    // Mirrors PlanDayDetailDrawer's own mount effect: no synchronous setState
    // in the effect body itself, only inside the promise callbacks.
    api.get<ExerciseOption[]>(`/api/v1/exercises?name=&exclude_ids=${excludeExerciseIds.join(",")}`)
      .then((data) => setResults(data))
      .catch(() => setResults([]))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handleSearchChange(value: string) {
    setSearch(value);
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    searchTimerRef.current = setTimeout(() => fetchOptions(value, selected), 300);
  }

  function toggleSelect(option: ExerciseOption) {
    setSelected((prev) => {
      const exists = prev.some((e) => e.id === option.id);
      const next = exists ? prev.filter((e) => e.id !== option.id) : [...prev, option];
      return next;
    });
  }

  function goToConfigure() {
    setConfigs(Object.fromEntries(selected.map((s) => [s.id, { sets: 3, reps: 10 }])));
    setStep("configure");
  }

  function setExerciseConfig(id: number, patch: Partial<ExerciseConfig>) {
    setConfigs((prev) => ({
      ...prev,
      [id]: { sets: prev[id]?.sets ?? 3, reps: prev[id]?.reps ?? 10, ...patch },
    }));
  }

  async function handleSubmit() {
    setSubmitting(true);
    setError("");
    try {
      const result = await api.post<CreatedBlockResult>(`/api/v1/workout_days/${dayId}/blocks`, {
        block_type: blockType,
        rounds,
        rest_between_rounds_seconds: restBetweenRounds,
        exercises: selected.map((s) => ({
          exercise_id: s.id,
          sets: configs[s.id]?.sets ?? 3,
          reps: configs[s.id]?.reps ?? 10,
          rest_seconds: 0,
        })),
      });
      onCreated(result);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : `Erro ao criar ${label.toLowerCase()}.`);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] flex items-end bg-black/50" onClick={onClose}>
      <div
        className="max-h-[90vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-8 pt-4 dark:bg-gray-900"
        style={{ paddingBottom: "max(32px, var(--safe-area-bottom))" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200 dark:bg-gray-700" />
        <div className="flex items-center justify-between mt-2 mb-4">
          <h3 className="text-base font-bold text-gray-900 dark:text-gray-50">Criar {label}</h3>
          <button onClick={onClose} className="text-sm text-gray-400 hover:text-gray-600 dark:hover:text-gray-300">Fechar</button>
        </div>

        {error && <p className="mb-3 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{error}</p>}

        {step === "pick_exercises" && (
          <>
            <p className="mb-2 text-xs text-gray-400">
              Escolha {blockType === "superset" ? "2 exercícios" : "3 ou mais exercícios"} para o {label.toLowerCase()}.
            </p>
            <input
              type="text"
              value={search}
              onChange={(e) => handleSearchChange(e.target.value)}
              placeholder="Buscar exercício..."
              className="mb-3 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:border-primary-500 focus:outline-none"
            />

            {selected.length > 0 && (
              <div className="mb-3 flex flex-wrap gap-2">
                {selected.map((s, idx) => (
                  <span key={s.id} className="flex items-center gap-1 rounded-full bg-primary-50 px-3 py-1 text-xs font-semibold text-primary-700">
                    A{idx + 1} · {s.name}
                    <button onClick={() => toggleSelect(s)} className="text-primary-400 hover:text-primary-600">×</button>
                  </span>
                ))}
              </div>
            )}

            {loading ? (
              <p className="rounded-lg bg-gray-50 p-3 text-center text-sm text-gray-400">Buscando...</p>
            ) : results.length === 0 ? (
              <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">Nenhum exercício encontrado.</p>
            ) : (
              <div className="space-y-2">
                {results.map((opt) => {
                  const isSelected = selected.some((s) => s.id === opt.id);
                  return (
                    <button
                      key={opt.id}
                      onClick={() => toggleSelect(opt)}
                      className={`flex w-full items-center gap-3 rounded-lg border p-2 text-left hover:bg-gray-50 ${
                        isSelected ? "border-primary-500 bg-primary-50" : "border-gray-100"
                      }`}
                    >
                      <img
                        src={getGymSafeImageUrl(opt) ?? `/exercise-images/${opt.exercise_type || "treino"}.svg`}
                        alt={opt.name}
                        className="h-12 w-16 flex-shrink-0 rounded-md object-cover"
                        onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = `/exercise-images/${opt.exercise_type || "treino"}.svg`; }}
                      />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-gray-900">{opt.name}</p>
                        <p className="text-xs text-gray-400">{opt.muscle_group ?? opt.exercise_type}</p>
                      </div>
                      {isSelected && <span className="text-primary-500">✓</span>}
                    </button>
                  );
                })}
              </div>
            )}

            <button
              onClick={goToConfigure}
              disabled={!isValidBlockSize(blockType, selected.length)}
              className="mt-4 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-40"
            >
              Continuar ({selected.length}/{minExercises}{blockType === "circuit" ? "+" : ""})
            </button>
          </>
        )}

        {step === "configure" && (
          <>
            <div className="mb-4 grid grid-cols-2 gap-3">
              <div>
                <label className="mb-1 block text-xs text-gray-400">Rodadas</label>
                <input
                  type="number" min={1} max={10} value={rounds}
                  onChange={(e) => setRounds(Math.max(1, parseInt(e.target.value, 10) || 1))}
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs text-gray-400">Descanso após rodada (s)</label>
                <input
                  type="number" min={0} max={600} step={15} value={restBetweenRounds}
                  onChange={(e) => setRestBetweenRounds(Math.max(0, parseInt(e.target.value, 10) || 0))}
                  className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                />
              </div>
            </div>

            <div className="space-y-3">
              {selected.map((s, idx) => (
                <div key={s.id} className="rounded-xl border border-gray-100 p-3">
                  <p className="mb-2 text-sm font-semibold text-gray-900">A{idx + 1} · {s.name}</p>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="mb-1 block text-xs text-gray-400">Séries</label>
                      <input
                        type="number" min={1} max={10} value={configs[s.id]?.sets ?? 3}
                        onChange={(e) => setExerciseConfig(s.id, { sets: Math.max(1, parseInt(e.target.value, 10) || 1) })}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-gray-400">Reps</label>
                      <input
                        type="number" min={1} max={100} value={configs[s.id]?.reps ?? 10}
                        onChange={(e) => setExerciseConfig(s.id, { reps: Math.max(1, parseInt(e.target.value, 10) || 1) })}
                        className="w-full rounded-lg border border-gray-200 px-3 py-2 text-center text-sm font-semibold focus:border-primary-500 focus:outline-none"
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <button
              onClick={() => setStep("pick_exercises")}
              className="mt-4 w-full rounded-xl border border-gray-200 py-2 text-sm font-semibold text-gray-600 dark:border-gray-700 dark:text-gray-300"
            >
              Voltar
            </button>
            <button
              onClick={handleSubmit}
              disabled={submitting}
              className="mt-2 w-full rounded-xl bg-primary-500 py-3 text-sm font-semibold text-white disabled:opacity-50"
            >
              {submitting ? "Criando..." : `Criar ${label}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
