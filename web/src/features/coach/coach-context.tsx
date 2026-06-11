"use client";

import { createContext, useCallback, useContext, useRef, useState } from "react";
import { api } from "@/shared/lib/api";

export type CoachMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  alternatives?: ExerciseAlternative[];
  appliedAlternativeId?: number;
  quickReplies?: string[];
};

export type ExerciseAlternative = {
  id: number;
  name: string;
  muscle_group: string | null;
  exercise_type: string;
  description: string;
  image_url: string;
  gif_url?: string | null;
};

export type ExecContext = {
  exerciseId: number;
  workoutDayExerciseId: number;
  exerciseName: string;
  muscleGroup: string | null;
  exerciseType?: string;
  currentIndex: number;
  setInfo?: string;
};

type SwapCallback = (workoutDayExerciseId: number, newExerciseId: number) => void;

interface CoachContextType {
  isOpen: boolean;
  messages: CoachMessage[];
  busy: boolean;
  currentScreen: string;
  execContext: ExecContext | null;
  open: (opts?: { intent?: "swap" }) => void;
  close: () => void;
  sendMessage: (text: string) => void;
  setScreen: (screen: string) => void;
  registerExec: (ctx: ExecContext | null, onSwap: SwapCallback | null) => void;
  applySwap: (msgId: string, alternative: ExerciseAlternative) => void;
}

const CoachContext = createContext<CoachContextType | null>(null);

const SWAP_REGEX =
  /(outr[ao]\s+(op[çc][ãa]o|exerc|alternativa)|trocar|substitu|alternativ|outro\s+exerc|n[ãa]o\s+gostei|enjoei)/i;

// Detects when the user wants a cardio modality (bike, running, etc.)
const MODALITY_CHANGE_REGEX =
  /\b(bike|bicicleta|corrida|correr|caminhada|nata[çc][ãa]o|nadar|el[íi]ptico|eliptico|esteira|remo|escada)\b/i;

// Matches "Trocar este exercício por X" quick-reply
const CARDIO_SWAP_REPLY_REGEX = /^trocar\s+este\s+exerc[íi]cio\s+por/i;

// Matches "Manter treino atual" quick-reply
const KEEP_TRAINING_REGEX = /^manter\s+treino/i;

// Matches "Criar treino rápido de X" quick-reply
const QUICK_WORKOUT_REGEX = /^criar\s+treino\s+r[áa]pido/i;

// Exercise types that are classified as strength (not cardio)
const STRENGTH_EXERCISE_TYPES = new Set(["musculacao", "strength"]);

function detectRequestedCardio(text: string): string {
  if (/bike|bicicleta/i.test(text)) return "bike";
  if (/corrida|correr/i.test(text)) return "corrida";
  if (/caminhada/i.test(text)) return "caminhada";
  if (/nata/i.test(text)) return "natação";
  if (/eliptico|el[íi]ptico|esteira/i.test(text)) return "elíptico";
  if (/remo/i.test(text)) return "remo";
  return "cardio";
}

function uid() {
  return Math.random().toString(36).slice(2);
}

function buildInitialGreeting(screen: string, execCtx: ExecContext | null): CoachMessage {
  let content: string;
  if (screen === "exec" && execCtx) {
    content = `Estou aqui durante o **${execCtx.exerciseName}**. Como posso ajudar?`;
  } else if (screen === "day" || screen === "plan") {
    content = "Oi! Posso montar ou ajustar seu treino. O que precisa?";
  } else {
    content = "Coach EasyHealth aqui. Pergunta sobre treino, carga ou evolução — pode mandar.";
  }
  return { id: uid(), role: "assistant", content };
}

export function CoachProvider({ children }: { children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<CoachMessage[]>([]);
  const [busy, setBusy] = useState(false);
  const [currentScreen, setCurrentScreen] = useState("dashboard");
  const [execContext, setExecContext] = useState<ExecContext | null>(null);
  const swapCallbackRef = useRef<SwapCallback | null>(null);
  const greetedRef = useRef(false);

  const setScreen = useCallback((screen: string) => {
    setCurrentScreen(screen);
  }, []);

  const registerExec = useCallback((ctx: ExecContext | null, onSwap: SwapCallback | null) => {
    setExecContext(ctx);
    swapCallbackRef.current = onSwap;
  }, []);

  const open = useCallback(
    (opts?: { intent?: "swap" }) => {
      setIsOpen(true);
      if (!greetedRef.current) {
        greetedRef.current = true;
        setMessages([buildInitialGreeting(currentScreen, execContext)]);
      }
      if (opts?.intent === "swap" && execContext) {
        setTimeout(() => {
          sendMessageInternal("Quero outra opção pra esse exercício");
        }, 300);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [currentScreen, execContext]
  );

  const close = useCallback(() => {
    setIsOpen(false);
  }, []);

  const sendMessageInternal = useCallback(
    async (text: string) => {
      if (busy) return;
      const userMsg: CoachMessage = { id: uid(), role: "user", content: text };
      setMessages((prev) => [...prev, userMsg]);
      setBusy(true);

      const isInExec = currentScreen === "exec" && !!execContext;

      try {
        // ── Quick-reply: "Manter treino atual" ───────────────────────────────
        if (KEEP_TRAINING_REGEX.test(text)) {
          setMessages((prev) => [
            ...prev,
            { id: uid(), role: "assistant", content: "Combinado! Qualquer dúvida sobre o treino, estou aqui. 💪" },
          ]);
          return;
        }

        // ── Quick-reply: "Criar treino rápido de X" ─────────────────────────
        if (QUICK_WORKOUT_REGEX.test(text)) {
          setMessages((prev) => [
            ...prev,
            {
              id: uid(),
              role: "assistant",
              content:
                "Para criar um treino rápido, acesse **Treinos → Treino Rápido** no menu. Ou pode continuar o treino atual!",
              quickReplies: ["Manter treino atual"],
            },
          ]);
          return;
        }

        // ── Quick-reply: "Trocar este exercício por X" ───────────────────────
        if (CARDIO_SWAP_REPLY_REGEX.test(text) && isInExec) {
          const params = new URLSearchParams({
            exercise_type: "cardio",
            exclude_ids: String(execContext!.exerciseId),
            per_page: "3",
          });
          const alts = await api.get<ExerciseAlternative[]>(`/api/v1/exercises?${params}`);
          setMessages((prev) => [
            ...prev,
            {
              id: uid(),
              role: "assistant",
              content: `Aqui estão opções de cardio para substituir o **${execContext!.exerciseName}**:`,
              alternatives: alts.slice(0, 3),
            },
          ]);
          return;
        }

        // ── Modality change detected: user requests cardio while doing strength ──
        const isModalityChange =
          isInExec &&
          execContext!.exerciseType &&
          STRENGTH_EXERCISE_TYPES.has(execContext!.exerciseType) &&
          MODALITY_CHANGE_REGEX.test(text);

        if (isModalityChange) {
          const requested = detectRequestedCardio(text);
          setMessages((prev) => [
            ...prev,
            {
              id: uid(),
              role: "assistant",
              content: `Boa! Você quer **${requested}** aqui no treino de hoje ou criar um treino separado?`,
              quickReplies: [
                `Trocar este exercício por ${requested}`,
                `Criar treino rápido de ${requested}`,
                "Manter treino atual",
              ],
            },
          ]);
          return;
        }

        // ── Normal swap: user asks for an alternative ────────────────────────
        const isSwap = isInExec && SWAP_REGEX.test(text);

        if (isSwap) {
          const params = new URLSearchParams({
            exclude_ids: String(execContext!.exerciseId),
            per_page: "3",
          });
          // For cardio exercises filter by type; for strength filter by muscle group
          if (execContext!.exerciseType === "cardio" || execContext!.exerciseType === "hiit") {
            params.set("exercise_type", execContext!.exerciseType);
          } else if (execContext!.muscleGroup) {
            params.set("muscle_group", execContext!.muscleGroup);
          }
          const alts = await api.get<ExerciseAlternative[]>(`/api/v1/exercises?${params}`);
          setMessages((prev) => [
            ...prev,
            {
              id: uid(),
              role: "assistant",
              content: `Aqui estão 3 opções para substituir o **${execContext!.exerciseName}**:`,
              alternatives: alts.slice(0, 3),
            },
          ]);
          return;
        }

        // ── General Coach API call ────────────────────────────────────────────
        const history = messages
          .concat(userMsg)
          .slice(-6)
          .map((m) => ({ role: m.role, content: m.content }));

        const context = {
          screen: currentScreen,
          exercise_name: execContext?.exerciseName ?? "",
          muscle_group: execContext?.muscleGroup ?? "",
          set_info: execContext?.setInfo ?? "",
        };

        const data = await api.post<{ reply: string }>("/api/v1/coach/messages", {
          messages: history,
          context,
        });

        setMessages((prev) => [
          ...prev,
          { id: uid(), role: "assistant", content: data.reply },
        ]);
      } catch {
        setMessages((prev) => [
          ...prev,
          {
            id: uid(),
            role: "assistant",
            content: "Sem conexão com o servidor. Tente novamente em alguns segundos.",
          },
        ]);
      } finally {
        setBusy(false);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [busy, currentScreen, execContext, messages]
  );

  const sendMessage = useCallback(
    (text: string) => {
      sendMessageInternal(text);
    },
    [sendMessageInternal]
  );

  const applySwap = useCallback(
    (msgId: string, alternative: ExerciseAlternative) => {
      if (!execContext || !swapCallbackRef.current) return;
      swapCallbackRef.current(execContext.workoutDayExerciseId, alternative.id);
      setMessages((prev) =>
        prev.map((m) =>
          m.id === msgId ? { ...m, appliedAlternativeId: alternative.id } : m
        )
      );
      const confirm: CoachMessage = {
        id: uid(),
        role: "assistant",
        content: `**${alternative.name}** aplicado! Continue o treino quando estiver pronto. 💪`,
      };
      setMessages((prev) => [...prev, confirm]);
    },
    [execContext]
  );

  return (
    <CoachContext.Provider
      value={{
        isOpen,
        messages,
        busy,
        currentScreen,
        execContext,
        open,
        close,
        sendMessage,
        setScreen,
        registerExec,
        applySwap,
      }}
    >
      {children}
    </CoachContext.Provider>
  );
}

export function useCoach() {
  const ctx = useContext(CoachContext);
  if (!ctx) throw new Error("useCoach must be used inside CoachProvider");
  return ctx;
}
