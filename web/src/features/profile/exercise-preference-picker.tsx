"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import type { ExercisePreference } from "@/shared/types/health-profile";

type SearchResult = ExercisePreference;

interface ExercisePreferencePickerProps {
  label: string;
  hint: string;
  selected: ExercisePreference[];
  onChange: (exercises: ExercisePreference[]) => void;
}

export function ExercisePreferencePicker({ label, hint, selected, onChange }: ExercisePreferencePickerProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) {
      return;
    }

    let active = true;
    const timer = window.setTimeout(async () => {
      setLoading(true);
      try {
        const exercises = await api.get<SearchResult[]>(`/api/v1/exercises?name=${encodeURIComponent(term)}`);
        if (active) setResults(exercises.slice(0, 6));
      } catch {
        if (active) setResults([]);
      } finally {
        if (active) setLoading(false);
      }
    }, 250);

    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [query]);

  function add(exercise: ExercisePreference) {
    if (selected.some((item) => item.id === exercise.id)) return;
    onChange([...selected, exercise]);
    setQuery("");
    setResults([]);
  }

  function remove(exerciseId: number) {
    onChange(selected.filter((exercise) => exercise.id !== exerciseId));
  }

  return (
    <div>
      <label className="mb-1 block text-sm font-medium text-slate-300">{label}</label>
      <p className="mb-2 text-xs text-slate-500">{hint}</p>
      {selected.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-2">
          {selected.map((exercise) => (
            <button
              key={exercise.id}
              type="button"
              onClick={() => remove(exercise.id)}
              className="rounded-full bg-primary-500/20 px-3 py-1 text-xs font-semibold text-primary-300"
            >
              {exercise.name} ×
            </button>
          ))}
        </div>
      )}
      <input
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="Buscar exercício"
        className="w-full rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-white focus:border-primary-500 focus:outline-none"
      />
      {query.trim().length >= 2 && (loading || results.length > 0) && (
        <div className="mt-2 overflow-hidden rounded-xl border border-slate-700 bg-slate-900">
          {loading && <p className="px-3 py-2 text-xs text-slate-400">Buscando exercícios…</p>}
          {!loading && results.map((exercise) => (
            <button
              key={exercise.id}
              type="button"
              onClick={() => add(exercise)}
              disabled={selected.some((item) => item.id === exercise.id)}
              className="flex w-full items-center justify-between px-3 py-2 text-left text-sm text-slate-200 hover:bg-slate-800 disabled:opacity-40"
            >
              <span>{exercise.name}</span>
              <span className="text-xs text-slate-500">{exercise.muscle_group ?? ""}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
