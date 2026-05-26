"use client";

/* eslint-disable @next/next/no-img-element */

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/shared/lib/api";
import type { WorkoutDayExercise } from "@/shared/types/workout";

type EquipmentIdentification = {
  equipment_name: string;
  localized_name: string;
  confidence: number;
  muscle_groups: string[];
  compatible: boolean;
  reason: string;
};

type ExerciseOption = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  description: string;
  image_url: string;
  gif_url?: string | null;
  video_url?: string | null;
  muscle_image_url: string;
  is_favorite?: boolean;
};

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

const TYPE_LABELS: Record<string, string> = {
  musculacao: "Musculação", cardio: "Cardio", natacao: "Natação",
  corrida: "Corrida", funcional: "Funcional", caminhada: "Caminhada", hiit: "HIIT",
};

function muscleLabel(muscleGroup: string | null, exerciseType: string): string {
  if (muscleGroup) return MUSCLE_LABELS[muscleGroup] ?? muscleGroup;
  return TYPE_LABELS[exerciseType] ?? exerciseType;
}

function exerciseFallback(exercise: { exercise_type: string }) {
  return `/exercise-images/${exercise.exercise_type || "treino"}.svg`;
}

function SmartImage({ src, fallbackSrc, alt, className }: { src: string; fallbackSrc: string; alt: string; className: string }) {
  return (
    <img
      src={src}
      alt={alt}
      className={className}
      onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = fallbackSrc; }}
    />
  );
}

export function SwapModal({
  exercise,
  allWorkoutExerciseIds = [],
  onSwap,
  onClose,
}: {
  exercise: WorkoutDayExercise;
  allWorkoutExerciseIds?: number[];
  onSwap: (wdeId: number, replacementId: number) => Promise<void>;
  onClose: () => void;
}) {
  const [alternatives, setAlternatives] = useState<ExerciseOption[]>([]);
  const [swapSearch, setSwapSearch] = useState("");
  const [swapFilter, setSwapFilter] = useState<{ muscle_group?: string; exercise_type?: string } | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiSuggestions, setAiSuggestions] = useState<ExerciseOption[]>([]);
  const [aiIdentification, setAiIdentification] = useState<EquipmentIdentification | null>(null);
  const [aiError, setAiError] = useState<string | null>(null);
  const [searchLang, setSearchLang] = useState<"pt" | "en">("pt");
  const [onlyFavorites, setOnlyFavorites] = useState(false);
  const searchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const openSwapFetch = useCallback(async (wde: WorkoutDayExercise) => {
    const excludeIds = [...new Set([wde.exercise_id, ...allWorkoutExerciseIds])].join(",");
    const query = wde.muscle_group ? `muscle_group=${wde.muscle_group}` : `exercise_type=${wde.exercise_type}`;
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${query}&exclude_ids=${excludeIds}`);
    setAlternatives(data);
  }, [allWorkoutExerciseIds]);

  useEffect(() => {
    openSwapFetch(exercise);
  }, [exercise, openSwapFetch]);

  const fetchByName = useCallback(async (name: string, lang: "pt" | "en" = "pt") => {
    setSearchLoading(true);
    try {
      const excludeIds = [...new Set([exercise.exercise_id, ...allWorkoutExerciseIds])].join(",");
      const params = new URLSearchParams({ name, exclude_ids: excludeIds });
      if (exercise.muscle_group) params.set("muscle_group", exercise.muscle_group);
      else params.set("exercise_type", exercise.exercise_type);
      if (lang === "en") params.set("lang", "en");
      const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${params.toString()}`);
      setAlternatives(data);
    } finally {
      setSearchLoading(false);
    }
  }, [exercise.exercise_id, exercise.muscle_group, exercise.exercise_type, allWorkoutExerciseIds]);

  async function fetchByFilter(filter: { muscle_group?: string; exercise_type?: string }) {
    const compatibleGroup = exercise.muscle_group ?? null;
    const compatibleType = exercise.exercise_type;
    const isCompatible = compatibleGroup
      ? filter.muscle_group === compatibleGroup
      : filter.exercise_type === compatibleType;
    if (!isCompatible) return;

    setSearchLoading(true);
    setSwapFilter(filter);
    try {
      const excludeIds = [...new Set([exercise.exercise_id, ...allWorkoutExerciseIds])].join(",");
      const params = new URLSearchParams({ exclude_ids: excludeIds });
      if (filter.muscle_group) params.set("muscle_group", filter.muscle_group);
      if (filter.exercise_type) params.set("exercise_type", filter.exercise_type);
      const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${params.toString()}`);
      setAlternatives(data);
    } finally {
      setSearchLoading(false);
    }
  }

  function handleSearchChange(value: string) {
    setSwapSearch(value);
    setSwapFilter(null);
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    if (value.trim().length >= 2) {
      searchTimerRef.current = setTimeout(() => fetchByName(value.trim(), searchLang), 300);
    } else if (value.trim().length === 0) {
      openSwapFetch(exercise);
    }
  }

  function handleLangChange(lang: "pt" | "en") {
    setSearchLang(lang);
    if (swapSearch.trim().length >= 2) {
      if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
      fetchByName(swapSearch.trim(), lang);
    }
  }

  async function toggleFavorite(exerciseId: number, currentlyFav: boolean) {
    try {
      if (currentlyFav) {
        await api.delete(`/api/v1/exercises/${exerciseId}/favorite`);
      } else {
        await api.post(`/api/v1/exercises/${exerciseId}/favorite`, {});
      }
      setAlternatives((prev) =>
        prev.map((e) => e.id === exerciseId ? { ...e, is_favorite: !currentlyFav } : e)
      );
    } catch {
      // ignore favorite toggle errors silently
    }
  }

  const displayedAlternatives = onlyFavorites
    ? alternatives.filter((a) => a.is_favorite)
    : alternatives;

  async function handleAiPhoto(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setAiLoading(true);
    setAiSuggestions([]);
    setAiIdentification(null);
    setAiError(null);
    try {
      const form = new FormData();
      form.append("image", file);
      form.append("exercise_id", String(exercise.exercise_id));
      const result = await api.uploadPost<{ identification: EquipmentIdentification | null; suggestions: ExerciseOption[] }>("/api/v1/exercises/ai_substitute", form);
      setAiIdentification(result.identification ?? null);
      setAiSuggestions(result.suggestions ?? []);
    } catch {
      setAiError("Não foi possível identificar o aparelho. Tente com outra foto.");
    } finally {
      setAiLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-black/40" onClick={onClose}>
      <div
        className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
        <h3 className="mb-3 mt-2 text-base font-bold text-gray-900">Escolha um substituto</h3>

        {/* Upload IA */}
        <div className="mb-4 rounded-xl border border-primary-100 bg-primary-50 p-3">
          <p className="mb-2 text-sm text-gray-700">Está com dúvida em algum aparelho? Tire uma foto dele e a gente explica qual é e se serve pra troca.</p>
          {aiLoading ? (
            <p className="py-1 text-center text-sm text-gray-400">Analisando foto...</p>
          ) : (
            <label className="flex cursor-pointer items-center gap-2 text-sm text-primary-600">
              📷 Tirar foto do aparelho
              <input type="file" accept="image/*" capture="environment" className="hidden" onChange={handleAiPhoto} />
            </label>
          )}

          {aiError && (
            <p className="mt-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-600">{aiError}</p>
          )}

          {aiIdentification && (
            <div className="mt-3 rounded-lg bg-white border border-primary-200 p-3">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-sm font-semibold text-gray-900">{aiIdentification.localized_name}</p>
                  <p className="text-xs text-gray-400">{aiIdentification.equipment_name}</p>
                </div>
                <span className={`flex-shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${aiIdentification.compatible ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-500"}`}>
                  {aiIdentification.compatible ? "Compatível" : "Incompatível"}
                </span>
              </div>
              {aiIdentification.confidence < 0.5 && (
                <p className="mt-1 text-xs text-amber-600">Foto pouco clara. Tente de outro ângulo.</p>
              )}
              {aiIdentification.reason && (
                <p className="mt-1 text-xs text-gray-500">{aiIdentification.reason}</p>
              )}
              {aiIdentification.muscle_groups.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-1">
                  {aiIdentification.muscle_groups.map((g) => (
                    <span key={g} className="rounded-full bg-primary-50 px-2 py-0.5 text-xs text-primary-600">{g}</span>
                  ))}
                </div>
              )}
            </div>
          )}

          {aiSuggestions.map((alt) => (
            <button
              key={`ai-${alt.id}`}
              onClick={() => onSwap(exercise.workout_day_exercise_id, alt.id)}
              className="mb-2 mt-2 flex w-full gap-3 rounded-lg border border-primary-200 bg-white p-3 text-left hover:bg-primary-100"
            >
              <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
              <div>
                <p className="font-medium text-gray-900">{alt.name}</p>
                <p className="text-xs text-primary-500">{muscleLabel(alt.muscle_group, alt.exercise_type)} · sugerido por IA</p>
              </div>
            </button>
          ))}
        </div>

        {/* Toggle de idioma + campo de busca */}
        <div className="mb-3 flex items-center gap-2">
          <div className="flex rounded-xl border border-gray-200 overflow-hidden">
            <button
              onClick={() => handleLangChange("pt")}
              className={`px-3 py-2 text-xs font-semibold transition ${searchLang === "pt" ? "bg-primary-500 text-white" : "bg-white text-gray-500 hover:bg-gray-50"}`}
            >
              🇧🇷 PT
            </button>
            <button
              onClick={() => handleLangChange("en")}
              className={`px-3 py-2 text-xs font-semibold transition ${searchLang === "en" ? "bg-primary-500 text-white" : "bg-white text-gray-500 hover:bg-gray-50"}`}
            >
              🇺🇸 EN
            </button>
          </div>
          <input
            type="text"
            placeholder={searchLang === "en" ? "Search by name..." : "Buscar por nome..."}
            value={swapSearch}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="flex-1 rounded-xl border border-gray-200 px-4 py-2.5 text-sm focus:border-primary-500 focus:outline-none"
          />
        </div>

        {/* Filtro somente favoritos */}
        <div className="mb-2 flex gap-2">
          <button
            onClick={() => setOnlyFavorites((v) => !v)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${onlyFavorites ? "bg-orange-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-orange-50"}`}
          >
            {onlyFavorites ? "❤️ Somente favoritos" : "🤍 Todos"}
          </button>
        </div>

        {/* Chips de filtro por músculo/tipo */}
        <div className="mb-3 flex flex-wrap gap-1.5">
          {Object.entries(MUSCLE_LABELS).map(([key, label]) => {
            const isCompatible = exercise.muscle_group === key;
            return (
              <button
                key={key}
                onClick={() => fetchByFilter({ muscle_group: key })}
                disabled={!isCompatible}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  swapFilter?.muscle_group === key
                    ? "bg-primary-500 text-white"
                    : isCompatible
                    ? "bg-gray-100 text-gray-600 hover:bg-primary-100"
                    : "cursor-not-allowed bg-gray-50 text-gray-300"
                }`}
              >
                {label}
              </button>
            );
          })}
          {Object.entries(TYPE_LABELS).map(([key, label]) => {
            const isCompatible = !exercise.muscle_group && exercise.exercise_type === key;
            return (
              <button
                key={key}
                onClick={() => fetchByFilter({ exercise_type: key })}
                disabled={!isCompatible}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  swapFilter?.exercise_type === key
                    ? "bg-primary-500 text-white"
                    : isCompatible
                    ? "bg-gray-100 text-gray-600 hover:bg-primary-100"
                    : "cursor-not-allowed bg-gray-50 text-gray-300"
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>

        {/* Lista de alternativas */}
        {searchLoading ? (
          <p className="rounded-lg bg-gray-50 p-3 text-center text-sm text-gray-400">Buscando...</p>
        ) : displayedAlternatives.length === 0 ? (
          <p className="rounded-lg bg-gray-50 p-3 text-sm text-gray-500">
            {onlyFavorites ? "Nenhum favorito encontrado para este grupo." : "Nenhuma alternativa encontrada."}
          </p>
        ) : (
          displayedAlternatives.map((alt) => (
            <div key={alt.id} className="mb-2 flex w-full items-center gap-1">
              <button
                onClick={() => onSwap(exercise.workout_day_exercise_id, alt.id)}
                className="flex flex-1 gap-3 rounded-lg border border-gray-100 p-3 text-left hover:bg-gray-50"
              >
                <SmartImage src={alt.image_url} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
                <div>
                  <p className="font-medium text-gray-900">{alt.name}</p>
                  <p className="text-xs text-gray-400">{muscleLabel(alt.muscle_group, alt.exercise_type)}</p>
                </div>
              </button>
              <button
                onClick={() => toggleFavorite(alt.id, !!alt.is_favorite)}
                className="flex-shrink-0 px-2 py-3 text-lg"
                title={alt.is_favorite ? "Remover dos favoritos" : "Adicionar aos favoritos"}
              >
                {alt.is_favorite ? "❤️" : "🤍"}
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
