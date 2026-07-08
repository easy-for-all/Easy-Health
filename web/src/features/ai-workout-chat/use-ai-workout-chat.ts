"use client";

import { useCallback, useRef, useState } from "react";
import { api, ApiError } from "@/shared/lib/api";
import type { WorkoutChatConversationStatus, WorkoutChatMessage, WorkoutChatPreview } from "./types";

interface StartResponse {
  status: WorkoutChatConversationStatus;
  reply: string;
  collected_profile: Record<string, unknown>;
}

interface MessageResponse {
  status: WorkoutChatConversationStatus;
  reply: string;
  collected_profile?: Record<string, unknown>;
  follow_up_rounds?: number;
  preview?: WorkoutChatPreview;
  blocked: boolean;
  block_reason?: "security_abuse" | "out_of_scope";
}

interface ConfirmResponse {
  status: "confirmed";
  workout_plan_id: number;
}

export type WorkoutChatPhase = "starting" | "collecting" | "previewing" | "confirming" | "confirmed" | "error";

export function useAiWorkoutChat() {
  const [phase, setPhase] = useState<WorkoutChatPhase>("starting");
  const [messages, setMessages] = useState<WorkoutChatMessage[]>([]);
  const [preview, setPreview] = useState<WorkoutChatPreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [workoutPlanId, setWorkoutPlanId] = useState<number | null>(null);
  const startedRef = useRef(false);

  const start = useCallback(async () => {
    if (startedRef.current) return;
    startedRef.current = true;
    setPhase("starting");
    setError(null);
    try {
      const data = await api.post<StartResponse>("/api/v1/ai/workout_chat/start", {});
      setMessages([{ role: "assistant", content: data.reply }]);
      setPhase(data.status === "previewing" ? "previewing" : "collecting");
    } catch (e) {
      startedRef.current = false;
      setError(e instanceof ApiError ? e.message : "Não foi possível iniciar o chat. Tente novamente.");
      setPhase("error");
    }
  }, []);

  const sendMessage = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed || busy) return;
    setBusy(true);
    setError(null);
    setMessages((prev) => [...prev, { role: "user", content: trimmed }]);
    try {
      const data = await api.post<MessageResponse>("/api/v1/ai/workout_chat/message", { message: trimmed });
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: data.reply, blocked: data.blocked, blockReason: data.block_reason },
      ]);
      if (data.preview) setPreview(data.preview);
      setPhase(data.status === "previewing" ? "previewing" : "collecting");
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Não consegui enviar sua mensagem. Tente novamente.");
    } finally {
      setBusy(false);
    }
  }, [busy]);

  const confirm = useCallback(async () => {
    setPhase("confirming");
    setError(null);
    try {
      const data = await api.post<ConfirmResponse>("/api/v1/ai/workout_chat/confirm", {});
      setWorkoutPlanId(data.workout_plan_id);
      setPhase("confirmed");
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Não conseguimos criar seu treino agora. Tente novamente.");
      setPhase("previewing");
    }
  }, []);

  return { phase, messages, preview, busy, error, workoutPlanId, start, sendMessage, confirm };
}
