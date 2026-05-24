"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";

interface PersonalTrainerRec {
  exercise: string;
  action: string;
  suggestion: string;
  reason: string;
  priority: "high" | "medium" | "low";
}

interface ConditioningRec {
  category: string;
  suggestion: string;
  reason: string;
  priority: "high" | "medium" | "low";
}

const ACTION_ICONS: Record<string, string> = {
  aumentar_peso: "↑",
  reduzir_peso: "↓",
  manter: "→",
  alterar_reps: "≈",
  alterar_series: "≈",
  deload: "⟳",
  progressao: "↑",
};

const CATEGORY_ICONS: Record<string, string> = {
  frequencia: "📅",
  duracao: "⏱",
  descanso: "💤",
  cardio: "🏃",
  circuito: "⚡",
  intensidade: "🔥",
};

const PRIORITY_STYLE: Record<string, string> = {
  high: "border-l-orange-400 bg-orange-50",
  medium: "border-l-primary-400 bg-primary-50",
  low: "border-l-gray-300 bg-gray-50",
};

export function AiRecommendationsCard() {
  const [ptRecs, setPtRecs] = useState<PersonalTrainerRec[]>([]);
  const [condRecs, setCondRecs] = useState<ConditioningRec[]>([]);
  const [ptMessage, setPtMessage] = useState<string | null>(null);
  const [condMessage, setCondMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    Promise.all([
      api.get<{ recommendations: PersonalTrainerRec[]; message?: string }>("/api/v1/ai_agents/personal_trainer").catch(() => null),
      api.get<{ recommendations: ConditioningRec[]; message?: string }>("/api/v1/ai_agents/conditioning").catch(() => null),
    ]).then(([pt, cond]) => {
      if (pt) { setPtRecs(pt.recommendations ?? []); if (pt.message) setPtMessage(pt.message); }
      if (cond) { setCondRecs(cond.recommendations ?? []); if (cond.message) setCondMessage(cond.message); }
      const total = (pt?.recommendations?.length ?? 0) + (cond?.recommendations?.length ?? 0);
      if (total > 0) {
        trackEvent(EVENTS.AI_TIP_VIEWED, { recommendations_count: total });
      }
    }).finally(() => setLoading(false));
  }, []);

  const allRecs = [...ptRecs, ...condRecs];
  if (loading) return null;
  if (allRecs.length === 0 && !ptMessage && !condMessage) return null;

  const highPriority = allRecs.filter((r) => r.priority === "high");
  const visibleRecs = expanded ? allRecs : allRecs.slice(0, 2);

  return (
    <div className="rounded-2xl border border-primary-100 bg-white overflow-hidden shadow-sm dark:border-primary-900 dark:bg-gray-900">
      <div className="flex items-center gap-2 px-4 py-3 bg-gradient-to-r from-primary-50 to-white dark:from-primary-950 dark:to-gray-900">
        <span className="text-lg">🤖</span>
        <div className="flex-1">
          <p className="text-sm font-bold text-gray-900 dark:text-gray-50">Personal IA</p>
          <p className="text-xs text-gray-400 dark:text-gray-500">Análise baseada no seu histórico</p>
        </div>
        {highPriority.length > 0 && (
          <span className="rounded-full bg-orange-100 px-2 py-0.5 text-xs font-semibold text-orange-600">
            {highPriority.length} urgente{highPriority.length > 1 ? "s" : ""}
          </span>
        )}
      </div>

      <div className="px-4 py-3 space-y-2">
        {(ptMessage || condMessage) && allRecs.length === 0 && (
          <p className="text-xs text-gray-500 italic">{ptMessage || condMessage}</p>
        )}

        {visibleRecs.map((rec, idx) => {
          const isPt = "exercise" in rec;
          if (isPt) {
            const r = rec as PersonalTrainerRec;
            return (
              <div key={idx} className={`rounded-xl border-l-4 p-3 ${PRIORITY_STYLE[r.priority] ?? PRIORITY_STYLE.medium}`}>
                <div className="flex items-start gap-2">
                  <span className="mt-0.5 text-base font-bold text-primary-600">{ACTION_ICONS[r.action] ?? "→"}</span>
                  <div>
                    <p className="text-xs font-semibold text-gray-700">{r.exercise}</p>
                    <p className="text-sm font-bold text-gray-900">{r.suggestion}</p>
                    <p className="mt-0.5 text-xs text-gray-500">{r.reason}</p>
                  </div>
                </div>
              </div>
            );
          } else {
            const r = rec as ConditioningRec;
            return (
              <div key={idx} className={`rounded-xl border-l-4 p-3 ${PRIORITY_STYLE[r.priority] ?? PRIORITY_STYLE.medium}`}>
                <div className="flex items-start gap-2">
                  <span className="mt-0.5 text-base">{CATEGORY_ICONS[r.category] ?? "💪"}</span>
                  <div>
                    <p className="text-sm font-bold text-gray-900">{r.suggestion}</p>
                    <p className="mt-0.5 text-xs text-gray-500">{r.reason}</p>
                  </div>
                </div>
              </div>
            );
          }
        })}

        {allRecs.length > 2 && (
          <button
            onClick={() => setExpanded((v) => !v)}
            className="w-full text-center text-xs font-medium text-primary-600 py-1"
          >
            {expanded ? "Ver menos" : `Ver mais ${allRecs.length - 2} recomendações`}
          </button>
        )}
      </div>
    </div>
  );
}
