"use client";

/* eslint-disable @next/next/no-img-element */

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/shared/lib/api";
import type { WorkoutDayExercise } from "@/shared/types/workout";
import { getGymSafeImageUrl } from "@/shared/utils/exercise-image";
import { AITrainerAvatar, AITrainerBubble } from "@/shared/components/ai-trainer";

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
  equipment_type?: string;
  description: string;
  image_url: string;
  gif_url?: string | null;
  video_url?: string | null;
  muscle_image_url: string;
  is_favorite?: boolean;
  reason?: string;
  score?: number;
};

type IntelligentSuggestionsResponse = {
  exercises: ExerciseOption[];
  intent: Record<string, unknown>;
  no_more: boolean;
  message?: string;
};

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros",
  biceps: "Bíceps", triceps: "Tríceps", legs: "Pernas", core: "Core",
};

const MUSCLE_COLORS: Record<string, string> = {
  chest: "bg-red-100 text-red-700",
  back: "bg-blue-100 text-blue-700",
  shoulders: "bg-purple-100 text-purple-700",
  biceps: "bg-yellow-100 text-yellow-700",
  triceps: "bg-orange-100 text-orange-700",
  legs: "bg-green-100 text-green-700",
  core: "bg-teal-100 text-teal-700",
};

function contextLabel(current: WorkoutDayExercise, alt: ExerciseOption): string | null {
  if (alt.exercise_type !== current.exercise_type && !alt.muscle_group) return "Modalidade diferente";
  if (alt.muscle_group === current.muscle_group) return "Mesmo músculo principal";
  return null;
}

// PT-BR to EN synonym map for equipment/muscle search
const SEARCH_SYNONYMS: Record<string, string[]> = {
  corda: ["rope", "corda"],
  barra: ["barbell", "barra", "bar"],
  cabo: ["cable", "cabo"],
  halter: ["dumbbell", "halteres", "halter"],
  halteres: ["dumbbell", "halteres"],
  peito: ["chest", "peitoral", "peito"],
  triceps: ["triceps", "tríceps"],
  costas: ["back", "costas", "dorsal"],
  pernas: ["legs", "quadriceps", "pernas"],
  biceps: ["biceps", "bíceps", "curl"],
  ombro: ["shoulder", "shoulders", "ombro"],
  ombros: ["shoulder", "shoulders", "ombros"],
  core: ["core", "abdomen", "abdominal", "abs"],
  abdominal: ["core", "abdomen", "abdominal"],
  maquina: ["machine", "máquina"],
};

function expandSearchTerm(term: string): string {
  const normalized = term.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
  const synonyms = SEARCH_SYNONYMS[normalized];
  if (synonyms) return synonyms[0];
  return normalized;
}

function parseEquipmentIntent(text: string): string | null {
  const t = text.toLowerCase();
  if (/\bcorda\b|rope/i.test(t)) return "corda";
  if (/\bbarra\b|barbell/i.test(t)) return "barra";
  if (/\bcabo\b|cable/i.test(t)) return "cabo";
  if (/\bhalter(es)?\b|dumbbell/i.test(t)) return "halteres";
  if (/\bm[aá]quina\b|machine/i.test(t)) return "maquina";
  return null;
}

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
  const [swapFilter, setSwapFilter] = useState<{ muscle_group?: string; exercise_type?: string; quick?: string } | null>(null);
  const [searchLoading, setSearchLoading] = useState(false);
  const [aiLoading, setAiLoading] = useState(false);
  const [aiSuggestions, setAiSuggestions] = useState<ExerciseOption[]>([]);
  const [aiIdentification, setAiIdentification] = useState<EquipmentIdentification | null>(null);
  const [aiError, setAiError] = useState<string | null>(null);
  const [searchLang, setSearchLang] = useState<"pt" | "en">("pt");
  const [searchFocused, setSearchFocused] = useState(false);
  const [onlyFavorites, setOnlyFavorites] = useState(false);
  const [favoritesLoading, setFavoritesLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [shownIds, setShownIds] = useState<Set<number>>(new Set());
  const [noMoreOptions, setNoMoreOptions] = useState(false);
  const [noMoreMessage, setNoMoreMessage] = useState<string | null>(null);
  const [lastIntent, setLastIntent] = useState<Record<string, unknown> | null>(null);
  const searchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  function trackShownIds(data: ExerciseOption[]) {
    setShownIds((prev) => new Set([...prev, ...data.map((d) => d.id)]));
  }

  const openSwapFetch = useCallback(async (wde: WorkoutDayExercise, additionalExcludes: number[] = []) => {
    const excludeIds = [...new Set([wde.exercise_id, ...allWorkoutExerciseIds, ...additionalExcludes])].join(",");
    const query = wde.muscle_group ? `muscle_group=${wde.muscle_group}` : `exercise_type=${wde.exercise_type}`;
    const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${query}&exclude_ids=${excludeIds}`);
    setAlternatives(data);
    trackShownIds(data);
    setNoMoreOptions(data.length === 0 && additionalExcludes.length > 0);
    setInitialLoading(false);
  }, [allWorkoutExerciseIds]);

  const fetchFavorites = useCallback(async (wde: WorkoutDayExercise) => {
    setFavoritesLoading(true);
    try {
      const excludeIds = [...new Set([wde.exercise_id, ...allWorkoutExerciseIds])].join(",");
      const query = wde.muscle_group ? `muscle_group=${wde.muscle_group}` : `exercise_type=${wde.exercise_type}`;
      const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${query}&only_favorites=true&exclude_ids=${excludeIds}`);
      setAlternatives(data);
    } finally {
      setFavoritesLoading(false);
    }
  }, [allWorkoutExerciseIds]);

  useEffect(() => {
    openSwapFetch(exercise);
  }, [exercise, openSwapFetch]);

  const fetchByName = useCallback(async (name: string, additionalExcludes: number[] = []) => {
    setSearchLoading(true);
    setNoMoreOptions(false);
    try {
      const excludeIds = [...new Set([exercise.exercise_id, ...allWorkoutExerciseIds, ...additionalExcludes])].join(",");
      const expandedName = expandSearchTerm(name);
      const params = new URLSearchParams({ name: expandedName, exclude_ids: excludeIds });
      if (swapFilter?.muscle_group) params.set("muscle_group", swapFilter.muscle_group);
      if (swapFilter?.exercise_type) params.set("exercise_type", swapFilter.exercise_type);
      const data = await api.get<ExerciseOption[]>(`/api/v1/exercises?${params.toString()}`);
      setAlternatives(data);
      trackShownIds(data);
      if (data.length === 0 && additionalExcludes.length > 0) {
        setNoMoreOptions(true);
      }
    } finally {
      setSearchLoading(false);
    }
  }, [exercise.exercise_id, exercise.muscle_group, exercise.exercise_type, allWorkoutExerciseIds, swapFilter]);

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

  const fetchIntelligentSuggestions = useCallback(async (userText: string, additionalExcludes: number[] = []) => {
    setSearchLoading(true);
    setNoMoreOptions(false);
    setNoMoreMessage(null);
    try {
      const alreadyIds = [...new Set([...shownIds, ...additionalExcludes])].join(",");
      const result = await api.post<IntelligentSuggestionsResponse>("/api/v1/exercises/intelligent_suggestions", {
        current_exercise_id:   exercise.exercise_id,
        user_text:             userText,
        already_suggested_ids: alreadyIds,
        per_page:              5,
      });
      setAlternatives(result.exercises);
      setLastIntent(result.intent ?? null);
      if (result.no_more) {
        setNoMoreOptions(true);
        setNoMoreMessage(result.message ?? "Não encontrei novas opções com esse critério. Posso ampliar para exercícios parecidos?");
      } else {
        trackShownIds(result.exercises);
      }
    } finally {
      setSearchLoading(false);
    }
  }, [exercise.exercise_id, shownIds]);

  function handleSearchChange(value: string) {
    setSwapSearch(value);
    setNoMoreOptions(false);
    setNoMoreMessage(null);
    if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
    if (value.trim().length >= 3) {
      searchTimerRef.current = setTimeout(() => fetchIntelligentSuggestions(value.trim()), 350);
    } else if (value.trim().length >= 2) {
      const term = parseEquipmentIntent(value.trim()) ?? value.trim();
      searchTimerRef.current = setTimeout(() => fetchByName(term), 300);
    } else if (value.trim().length === 0) {
      openSwapFetch(exercise);
    }
  }

  function handleLangChange(lang: "pt" | "en") {
    setSearchLang(lang);
    if (swapSearch.trim().length >= 2) {
      if (searchTimerRef.current) clearTimeout(searchTimerRef.current);
      const term = parseEquipmentIntent(swapSearch.trim()) ?? swapSearch.trim();
      fetchByName(term);
    }
  }

  function handleMoreOptions() {
    setNoMoreOptions(false);
    setNoMoreMessage(null);
    if (swapSearch.trim().length >= 3) {
      fetchIntelligentSuggestions(swapSearch.trim(), [...shownIds]);
    } else if (swapSearch.trim().length >= 2) {
      const term = parseEquipmentIntent(swapSearch.trim()) ?? swapSearch.trim();
      fetchByName(term, [...shownIds]);
    } else {
      openSwapFetch(exercise, [...shownIds]);
    }
  }

  async function sendSuggestionFeedback(exerciseId: number, eventType: string) {
    try {
      await api.post(`/api/v1/exercises/${exerciseId}/suggestion_feedback`, {
        event_type:          eventType,
        current_exercise_id: exercise.exercise_id,
        intent_text:         swapSearch,
        parsed_intent:       lastIntent ?? {},
      });
    } catch {
      // non-critical — ignore failures silently
    }
  }

  function handleResetAndSearch() {
    setShownIds(new Set());
    setNoMoreOptions(false);
    openSwapFetch(exercise);
  }

  function handleClearFilters() {
    setSwapSearch("");
    setSwapFilter(null);
    setOnlyFavorites(false);
    setNoMoreOptions(false);
    setNoMoreMessage(null);
    openSwapFetch(exercise);
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

  async function handleToggleOnlyFavorites() {
    const next = !onlyFavorites;
    setOnlyFavorites(next);
    setNoMoreOptions(false);
    if (next) {
      await fetchFavorites(exercise);
    } else {
      await openSwapFetch(exercise);
    }
  }

  const displayedAlternatives = alternatives;

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
        className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-4 pb-24 pt-4 dark:bg-gray-900"
        style={{ paddingBottom: "max(96px, var(--safe-area-bottom))" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />

        {/* AI Trainer header */}
        <div className="mb-4 mt-2 flex items-start gap-3">
          <AITrainerAvatar mood={initialLoading ? "thinking" : "speaking"} size="sm" />
          <AITrainerBubble
            message={
              initialLoading
                ? "Buscando exercícios compatíveis..."
                : `${exercise.name} trabalha ${MUSCLE_LABELS[exercise.muscle_group ?? ""] || exercise.muscle_group || exercise.exercise_type}. Aqui estão as melhores alternativas.`
            }
            mood={initialLoading ? "thinking" : "speaking"}
            show
            side="left"
          />
        </div>

        {/* Current exercise mini-card */}
        <div className="mb-3 flex items-center gap-3 rounded-xl border border-dashed border-gray-200 bg-gray-50 px-3 py-2.5 dark:border-gray-700 dark:bg-gray-800/50">
          <SmartImage
            src={getGymSafeImageUrl(exercise) ?? exerciseFallback(exercise)}
            fallbackSrc={exerciseFallback(exercise)}
            alt={exercise.name}
            className="h-10 w-14 rounded-lg object-cover opacity-60"
          />
          <div className="min-w-0 flex-1">
            <p className="text-xs text-gray-400">Substituindo</p>
            <p className="truncate text-sm font-semibold text-gray-700 dark:text-gray-300">{exercise.name}</p>
          </div>
          {exercise.muscle_group && (
            <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-medium ${MUSCLE_COLORS[exercise.muscle_group] ?? "bg-gray-100 text-gray-600"}`}>
              {MUSCLE_LABELS[exercise.muscle_group] ?? exercise.muscle_group}
            </span>
          )}
        </div>

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
              <SmartImage src={getGymSafeImageUrl(alt) ?? exerciseFallback(alt)} fallbackSrc={exerciseFallback(alt)} alt={alt.name} className="h-12 w-16 rounded-md object-cover" />
              <div>
                <p className="font-medium text-gray-900">{alt.name}</p>
                <p className="text-xs text-primary-500">{muscleLabel(alt.muscle_group, alt.exercise_type)} · sugerido por IA</p>
              </div>
            </button>
          ))}
        </div>

        {/* Toggle de idioma + campo de busca */}
        <div className="mb-3 flex items-center gap-2">
          <div
            style={{
              overflow: "hidden",
              maxWidth: searchFocused || swapSearch.trim() ? 0 : 120,
              opacity: searchFocused || swapSearch.trim() ? 0 : 1,
              transition: "max-width 0.2s ease, opacity 0.2s ease",
              pointerEvents: searchFocused || swapSearch.trim() ? "none" : "auto",
              flexShrink: 0,
            }}
          >
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
          </div>
          <input
            type="text"
            placeholder={searchLang === "en" ? "Search by name..." : "Buscar por nome..."}
            value={swapSearch}
            onChange={(e) => handleSearchChange(e.target.value)}
            onFocus={() => setSearchFocused(true)}
            onBlur={() => setSearchFocused(false)}
            className="flex-1 rounded-xl border border-gray-200 px-4 py-2.5 text-sm focus:border-primary-500 focus:outline-none"
          />
        </div>

        {/* Filtro somente favoritos + filtros rápidos */}
        <div className="mb-2 flex flex-wrap gap-2">
          <button
            onClick={handleToggleOnlyFavorites}
            disabled={favoritesLoading}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${onlyFavorites ? "bg-orange-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-orange-50"}`}
          >
            {favoritesLoading ? "Carregando..." : onlyFavorites ? "❤️ Favoritos" : "🤍 Favoritos"}
          </button>
          <button
            onClick={() => { setSwapSearch("em casa"); setSwapFilter({ quick: "home" }); fetchIntelligentSuggestions("em casa"); }}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${swapFilter?.quick === "home" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-primary-50"}`}
          >
            🏠 Em casa
          </button>
          <button
            onClick={() => { setSwapSearch("cardio"); setSwapFilter({ quick: "cardio" }); fetchIntelligentSuggestions("quero cardio"); }}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${swapFilter?.quick === "cardio" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-primary-50"}`}
          >
            🏃 Cardio
          </button>
          <button
            onClick={() => { setSwapSearch("mais leve"); setSwapFilter({ quick: "lighter" }); fetchIntelligentSuggestions("mais leve"); }}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${swapFilter?.quick === "lighter" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-primary-50"}`}
          >
            🪶 Mais leve
          </button>
          <button
            onClick={() => { setSwapSearch("mais pesado"); setSwapFilter({ quick: "heavier" }); fetchIntelligentSuggestions("mais pesado"); }}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${swapFilter?.quick === "heavier" ? "bg-primary-500 text-white" : "bg-gray-100 text-gray-600 hover:bg-primary-50"}`}
          >
            🏋️ Mais pesado
          </button>
        </div>

        {/* Chips de filtro por músculo/tipo — com cores */}
        <div className="mb-3 flex flex-wrap gap-1.5">
          {Object.entries(MUSCLE_LABELS).map(([key, label]) => {
            const isCompatible = exercise.muscle_group === key;
            const isActive = swapFilter?.muscle_group === key;
            return (
              <button
                key={key}
                onClick={() => fetchByFilter({ muscle_group: key })}
                disabled={!isCompatible}
                className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
                  isActive
                    ? "bg-primary-500 text-white"
                    : isCompatible
                    ? `${MUSCLE_COLORS[key] ?? "bg-gray-100 text-gray-600"} hover:opacity-80`
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
          <div className="space-y-2.5">
            {[1, 2, 3].map((i) => (
              <div key={i} className="flex items-center gap-3 rounded-xl border border-gray-100 p-3 dark:border-gray-700">
                <div className="h-16 w-20 shrink-0 animate-pulse rounded-xl bg-gray-200 dark:bg-gray-700" />
                <div className="flex-1 space-y-2">
                  <div className="h-3 w-3/4 animate-pulse rounded bg-gray-200 dark:bg-gray-700" />
                  <div className="h-3 w-1/3 animate-pulse rounded bg-gray-200 dark:bg-gray-700" />
                </div>
              </div>
            ))}
          </div>
        ) : noMoreOptions ? (
          <div className="rounded-lg bg-gray-50 p-4 text-center dark:bg-gray-800">
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {noMoreMessage ?? "Não encontrei novas opções com esse critério. Posso ampliar para exercícios parecidos?"}
            </p>
            <button
              onClick={handleResetAndSearch}
              className="mt-2 text-xs font-semibold text-primary-500 underline"
            >
              Ampliar busca (ver todos os exercícios do grupo)
            </button>
          </div>
        ) : displayedAlternatives.length === 0 ? (
          <div className="rounded-lg bg-gray-50 p-4 text-center dark:bg-gray-800">
            {onlyFavorites ? (
              <>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  Você ainda não possui favoritos para {MUSCLE_LABELS[exercise.muscle_group ?? ""] || exercise.muscle_group || exercise.exercise_type}.
                </p>
                <button
                  onClick={() => { setOnlyFavorites(false); openSwapFetch(exercise); }}
                  className="mt-2 text-xs font-semibold text-primary-500 underline"
                >
                  Ver exercícios recomendados
                </button>
              </>
            ) : (
              <>
                <p className="text-sm text-gray-500 dark:text-gray-400">Nenhum exercício encontrado com esses filtros.</p>
                <button
                  onClick={handleClearFilters}
                  className="mt-2 text-xs font-semibold text-primary-500 underline"
                >
                  Limpar filtros
                </button>
              </>
            )}
          </div>
        ) : (
          <>
          {displayedAlternatives.map((alt) => {
            const ctx = !alt.reason ? contextLabel(exercise, alt) : null;
            const muscleColor = alt.muscle_group ? MUSCLE_COLORS[alt.muscle_group] : null;
            return (
              <div key={alt.id} className="mb-2.5 flex w-full items-center gap-1">
                <button
                  onClick={async () => {
                    await sendSuggestionFeedback(alt.id, "suggestion_accepted");
                    onSwap(exercise.workout_day_exercise_id, alt.id);
                  }}
                  className="flex flex-1 gap-3 rounded-xl border border-gray-100 p-3 text-left hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
                >
                  <SmartImage
                    src={getGymSafeImageUrl(alt) ?? exerciseFallback(alt)}
                    fallbackSrc={exerciseFallback(alt)}
                    alt={alt.name}
                    className="h-16 w-20 shrink-0 rounded-xl object-cover"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-gray-900 dark:text-gray-50 leading-tight">{alt.name}</p>
                    <div className="mt-1 flex flex-wrap gap-1">
                      {alt.muscle_group && (
                        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${muscleColor ?? "bg-gray-100 text-gray-600"}`}>
                          {MUSCLE_LABELS[alt.muscle_group] ?? alt.muscle_group}
                        </span>
                      )}
                      {ctx && (
                        <span className="rounded-full bg-primary-50 px-2 py-0.5 text-xs text-primary-600">
                          {ctx}
                        </span>
                      )}
                    </div>
                    {alt.reason && (
                      <p className="mt-1 text-xs text-gray-400 leading-snug">{alt.reason}</p>
                    )}
                  </div>
                </button>
                <button
                  onClick={() => toggleFavorite(alt.id, !!alt.is_favorite)}
                  className="shrink-0 px-2 py-3 text-lg"
                  title={alt.is_favorite ? "Remover dos favoritos" : "Adicionar aos favoritos"}
                >
                  {alt.is_favorite ? "❤️" : "🤍"}
                </button>
              </div>
            );
          })}
          {/* Other options button */}
          {displayedAlternatives.length > 0 && (
            <button
              onClick={handleMoreOptions}
              className="mt-1 w-full rounded-xl border border-dashed border-gray-200 py-3 text-sm font-medium text-gray-400 hover:border-primary-300 hover:text-primary-500 dark:border-gray-700 dark:hover:border-primary-700"
            >
              Outras opções →
            </button>
          )}
          </>
        )}
      </div>
    </div>
  );
}
