"use client";

import { useState } from "react";
import { api } from "@/shared/lib/api";
import type { WorkoutDayExercise } from "@/shared/types/workout";

const SECTION_HEADERS = ["COMO FAZER", "CONFIGURAÇÃO INICIAL", "ERROS COMUNS", "DICA PARA INICIANTE"];

function GuideRenderer({ text }: { text: string }) {
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const sections: { header: string; items: string[] }[] = [];
  let current: { header: string; items: string[] } | null = null;

  for (const line of lines) {
    const isHeader = SECTION_HEADERS.some((h) => line.toUpperCase().startsWith(h));
    if (isHeader) {
      if (current) sections.push(current);
      current = { header: line.replace(/[*#]/g, "").trim(), items: [] };
    } else if (current) {
      const clean = line.replace(/^[-*•]\s*/, "").replace(/\*\*/g, "").replace(/^#+\s*/, "");
      if (clean) current.items.push(clean);
    }
  }
  if (current) sections.push(current);

  if (sections.length === 0) {
    return (
      <div className="space-y-1 py-1">
        {lines.map((line, i) => {
          const clean = line.replace(/[*#]/g, "").replace(/^[-•]\s*/, "");
          return <p key={i} className="text-sm leading-relaxed text-gray-600">{clean}</p>;
        })}
      </div>
    );
  }

  return (
    <div className="space-y-4 py-1">
      {sections.map((section) => (
        <div key={section.header}>
          <p className="mb-1.5 text-xs font-bold uppercase tracking-wide text-blue-600">{section.header}</p>
          <div className="space-y-1">
            {section.items.map((item, i) => {
              const isNumbered = /^\d+\./.test(item);
              return (
                <div key={i} className="flex gap-2 text-sm text-gray-700">
                  {isNumbered ? (
                    <>
                      <span className="shrink-0 font-semibold text-blue-400">{item.match(/^\d+/)?.[0]}.</span>
                      <span>{item.replace(/^\d+\.\s*/, "")}</span>
                    </>
                  ) : (
                    <>
                      <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-blue-300" />
                      <span>{item}</span>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

export function ExerciseInfoModal({
  exercise,
  onClose,
  onToggleFavorite,
}: {
  exercise: WorkoutDayExercise | null;
  onClose: () => void;
  onToggleFavorite?: (exerciseId: number, currentlyFav: boolean) => void;
}) {
  const [setupGuide, setSetupGuide] = useState<string | null>(null);
  const [setupGuideLoading, setSetupGuideLoading] = useState(false);
  const [setupGuideOpen, setSetupGuideOpen] = useState(false);
  const [isFavorite, setIsFavorite] = useState<boolean | null>(null);
  const [favLoading, setFavLoading] = useState(false);

  if (!exercise) return null;

  const favState = isFavorite ?? (exercise as WorkoutDayExercise & { is_favorite?: boolean }).is_favorite ?? false;

  async function handleToggleFav() {
    if (favLoading) return;
    setFavLoading(true);
    const next = !favState;
    setIsFavorite(next);
    try {
      if (next) {
        await api.post(`/api/v1/exercises/${exercise!.exercise_id}/favorite`, {});
      } else {
        await api.delete(`/api/v1/exercises/${exercise!.exercise_id}/favorite`);
      }
      onToggleFavorite?.(exercise!.exercise_id, !next);
    } catch {
      setIsFavorite(favState);
    } finally {
      setFavLoading(false);
    }
  }

  async function handleSetupGuide() {
    if (setupGuide !== null) {
      setSetupGuideOpen((prev) => !prev);
      return;
    }
    setSetupGuideLoading(true);
    setSetupGuideOpen(true);
    try {
      const data = await api.get<{ setup_guide: string }>(`/api/v1/exercises/${exercise!.exercise_id}/setup_guide`);
      setSetupGuide(data.setup_guide ?? null);
    } catch {
      setSetupGuide("");
    } finally {
      setSetupGuideLoading(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end bg-black/50"
      onClick={onClose}
    >
      <div
        className="max-h-[85vh] w-full overflow-y-auto rounded-t-2xl bg-white px-5 pb-10 pt-5 dark:bg-gray-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-1 mx-auto h-1 w-10 rounded-full bg-gray-200" />
        <div className="mt-4 flex items-start justify-between gap-3">
          <h3 className="text-xl font-bold text-gray-900 dark:text-gray-50">{exercise.name}</h3>
          <button
            onClick={handleToggleFav}
            disabled={favLoading}
            className="shrink-0 text-2xl leading-none transition-transform active:scale-90 disabled:opacity-50"
            aria-label={favState ? "Remover dos favoritos" : "Adicionar aos favoritos"}
          >
            {favState ? "❤️" : "🤍"}
          </button>
        </div>
        <p className="mt-3 text-sm leading-relaxed text-gray-600 dark:text-gray-300">{exercise.description}</p>

        {exercise.instructions && (
          <div className="mt-4">
            <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">Como executar</p>
            <ol className="space-y-2">
              {exercise.instructions.split("\n").filter(Boolean).map((step, i) => (
                <li key={i} className="flex gap-2 text-sm text-gray-700 dark:text-gray-300">
                  <span className="flex-shrink-0 font-semibold text-primary-500">{i + 1}.</span>
                  {step}
                </li>
              ))}
            </ol>
          </div>
        )}

        {exercise.exercise_type === "musculacao" && (
          <div className="mt-6">
            <button
              onClick={handleSetupGuide}
              className="flex w-full items-center justify-between rounded-xl border border-blue-100 bg-blue-50 px-4 py-3 active:bg-blue-100"
            >
              <span className="flex items-center gap-2 text-sm font-semibold text-blue-700">
                ⚙ Configuração para iniciantes
              </span>
              <span className="text-xl font-light text-blue-400">
                {setupGuideOpen ? "−" : "+"}
              </span>
            </button>

            {setupGuideOpen && (
              <div className="mt-3 rounded-xl border border-blue-50 bg-white px-3 py-2">
                {setupGuideLoading ? (
                  <p className="py-6 text-center text-sm text-gray-400">Gerando guia pela primeira vez...</p>
                ) : setupGuide ? (
                  <GuideRenderer text={setupGuide} />
                ) : (
                  <p className="py-4 text-center text-sm text-red-400">
                    Não foi possível gerar o guia. Tente novamente.
                  </p>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
