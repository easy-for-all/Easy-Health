"use client";

import { useEffect, useState } from "react";
import { api } from "@/shared/lib/api";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";
import { AITrainerAvatar } from "./ai-trainer-avatar";
import { AITrainerBubble } from "./ai-trainer-bubble";

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

type Props = {
  /** Override the message instead of fetching from API */
  message?: string;
  /** Skip fetching recommendations from the API */
  staticOnly?: boolean;
  className?: string;
};

export function AITrainerCard({ message: staticMessage, staticOnly = false, className = "" }: Props) {
  const [message, setMessage] = useState(staticMessage ?? "");
  const [loading, setLoading] = useState(!staticOnly && !staticMessage);

  useEffect(() => {
    if (staticOnly || staticMessage) return;

    api
      .get<{ recommendations: PersonalTrainerRec[]; message?: string }>("/api/v1/ai_agents/personal_trainer")
      .then((data) => {
        const recs = data.recommendations ?? [];
        if (recs.length > 0) {
          const top = recs[0];
          setMessage(`${top.suggestion} — ${top.reason}`);
          trackEvent(EVENTS.AI_TIP_VIEWED, { recommendations_count: recs.length });
        } else if (data.message) {
          setMessage(data.message);
        } else {
          setMessage("Continue treinando! Consistência é a chave.");
        }
      })
      .catch(() => setMessage("Pronto para treinar? Vamos lá! 💪"))
      .finally(() => setLoading(false));
  }, [staticMessage, staticOnly]);

  if (loading) {
    return (
      <div className={`flex items-start gap-3 ${className}`}>
        <div className="h-14 w-14 animate-pulse rounded-full bg-primary-100 dark:bg-primary-900" />
        <div className="flex-1 space-y-2 pt-2">
          <div className="h-3 w-3/4 animate-pulse rounded bg-gray-200 dark:bg-gray-700" />
          <div className="h-3 w-1/2 animate-pulse rounded bg-gray-200 dark:bg-gray-700" />
        </div>
      </div>
    );
  }

  return (
    <div className={`flex items-start gap-3 ${className}`}>
      <div className="shrink-0">
        <AITrainerAvatar mood="speaking" size="md" />
        <p className="mt-1 text-center text-[10px] font-semibold tracking-wide text-primary-500 uppercase">
          Coach IA
        </p>
      </div>
      <div className="flex-1 pt-1">
        <AITrainerBubble message={message} mood="speaking" show={!!message} side="left" />
      </div>
    </div>
  );
}
