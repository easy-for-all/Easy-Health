"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { AgentOrb } from "@/shared/components/agent-orb";
import {
  useCoach,
  type CoachMessage,
  type ExerciseAlternative,
} from "@/features/coach/coach-context";
import { getGymSafeImageUrl } from "@/shared/utils/exercise-image";
import "./coach-sheet.css";

// ─── Quick chip sets ─────────────────────────────────────────────────────────

const CHIPS: Record<string, { label: string; text: string; swap?: boolean }[]> = {
  exec: [
    { label: "✦ Outra opção pra esse exercício", text: "Quero outra opção pra esse exercício", swap: true },
    { label: "Tá pesado demais", text: "Está pesado demais, o que faço?" },
    { label: "Como executar certo?", text: "Como executar esse exercício corretamente?" },
  ],
  day: [
    { label: "Treino de 30 min", text: "Quero um treino de 30 minutos" },
    { label: "Foca num músculo hoje", text: "Qual músculo focar hoje?" },
    { label: "Sem equipamento", text: "Quero exercícios sem equipamento" },
  ],
  plan: [
    { label: "Treino de 30 min", text: "Quero um treino de 30 minutos" },
    { label: "Foca num músculo hoje", text: "Qual músculo focar hoje?" },
    { label: "Sem equipamento", text: "Quero exercícios sem equipamento" },
  ],
  dashboard: [
    { label: "Como tá minha evolução?", text: "Como está minha evolução?" },
    { label: "Treino de hoje", text: "Qual o treino de hoje?" },
    { label: "O que treino amanhã?", text: "O que treino amanhã?" },
  ],
};

function getChips(screen: string) {
  return CHIPS[screen] ?? CHIPS.dashboard;
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function TypingIndicator() {
  return (
    <div className="coach-msg coach-msg--ai">
      <AgentOrb size="avatar" pulse />
      <div className="coach-bubble coach-bubble--ai">
        <span className="coach-dots">
          <span />
          <span />
          <span />
        </span>
      </div>
    </div>
  );
}

const MUSCLE_LABELS: Record<string, string> = {
  chest: "Peito", back: "Costas", shoulders: "Ombros", biceps: "Bíceps",
  triceps: "Tríceps", legs: "Pernas", core: "Core", glutes: "Glúteos",
  calves: "Panturrilha", forearms: "Antebraço",
};

const EXERCISE_TYPE_LABELS: Record<string, string> = {
  musculacao: "Força", cardio: "Cardio", hiit: "HIIT",
  funcional: "Funcional", corrida: "Corrida", caminhada: "Caminhada",
};

function AltCard({
  alt,
  applied,
  dimmed,
  onApply,
}: {
  alt: ExerciseAlternative;
  applied: boolean;
  dimmed: boolean;
  onApply: () => void;
}) {
  const imgSrc = getGymSafeImageUrl(alt) || `/exercise-images/${alt.exercise_type || "treino"}.svg`;
  const muscleLabel = alt.muscle_group ? (MUSCLE_LABELS[alt.muscle_group] ?? alt.muscle_group) : null;
  const typeLabel = EXERCISE_TYPE_LABELS[alt.exercise_type] ?? null;

  return (
    <div
      className={`coach-alt-card ${applied ? "coach-alt-card--applied" : ""} ${dimmed ? "coach-alt-card--dimmed" : ""}`}
    >
      {/* thumb */}
      <div className="coach-alt-thumb">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={imgSrc}
          alt={alt.name}
          className="coach-alt-img"
          onError={(e) => {
            e.currentTarget.src = `/exercise-images/${alt.exercise_type || "treino"}.svg`;
          }}
        />
      </div>

      {/* info */}
      <div className="coach-alt-info">
        <span className="coach-alt-name">{alt.name}</span>
        {alt.reason ? (
          <span className="coach-alt-desc" style={{ color: "oklch(0.6 0.02 262)" }}>{alt.reason}</span>
        ) : alt.description ? (
          <span className="coach-alt-desc">{alt.description.slice(0, 80)}</span>
        ) : null}
        <div className="coach-alt-tags">
          {muscleLabel && <span className="coach-alt-tag">{muscleLabel}</span>}
          {typeLabel && muscleLabel !== typeLabel && (
            <span className="coach-alt-tag coach-alt-tag--type">{typeLabel}</span>
          )}
        </div>
        <button
          onClick={onApply}
          disabled={applied || dimmed}
          aria-label={`Substituir por ${alt.name}`}
          className={`coach-alt-swap-btn ${applied ? "coach-alt-swap-btn--applied" : ""}`}
        >
          {applied ? "✓ Substituído" : "Substituir exercício"}
        </button>
      </div>
    </div>
  );
}

function MessageBubble({ msg }: { msg: CoachMessage }) {
  const { applySwap, applyWeightSuggestion, close, sendMessage, busy } = useCoach();
  const isAi = msg.role === "assistant";

  if (isAi) {
    return (
      <div className="coach-msg coach-msg--ai">
        <AgentOrb size="avatar" />
        <div className="coach-bubble-group">
          <div
            className="coach-bubble coach-bubble--ai"
            dangerouslySetInnerHTML={{ __html: renderMd(msg.content) }}
          />
          {msg.alternatives && msg.alternatives.length > 0 && (
            <div className="coach-alts">
              {msg.alternatives.map((alt) => (
                <AltCard
                  key={alt.id}
                  alt={alt}
                  applied={msg.appliedAlternativeId === alt.id}
                  dimmed={
                    msg.appliedAlternativeId !== undefined &&
                    msg.appliedAlternativeId !== alt.id
                  }
                  onApply={() => applySwap(msg.id, alt)}
                />
              ))}
              {msg.appliedAlternativeId !== undefined && (
                <button onClick={close} className="coach-see-workout-btn">
                  Ver na tela do treino →
                </button>
              )}
            </div>
          )}
          {msg.suggestedWeightKg && (
            <div style={{ marginTop: 8 }}>
              <button
                onClick={() => applyWeightSuggestion(msg.id, msg.suggestedWeightKg!)}
                disabled={msg.weightApplied}
                className={`coach-alt-swap-btn ${msg.weightApplied ? "coach-alt-swap-btn--applied" : ""}`}
                style={{ fontSize: 12 }}
              >
                {msg.weightApplied ? `✓ ${msg.suggestedWeightKg}kg aplicado` : `Aplicar ${msg.suggestedWeightKg}kg`}
              </button>
            </div>
          )}
          {msg.quickReplies && msg.quickReplies.length > 0 && (
            <div className="coach-quick-replies">
              {msg.quickReplies.map((reply) => (
                <button
                  key={reply}
                  className="coach-quick-reply-btn"
                  onClick={() => sendMessage(reply)}
                  disabled={busy}
                >
                  {reply}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="coach-msg coach-msg--user">
      <div className="coach-bubble coach-bubble--user">{msg.content}</div>
    </div>
  );
}

// Minimal bold/inline-code markdown renderer (no library dep)
function renderMd(text: string): string {
  return text
    .replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>")
    .replace(/`(.*?)`/g, "<code>$1</code>")
    .replace(/\n/g, "<br/>");
}

// ─── CoachSheet ───────────────────────────────────────────────────────────────

export function CoachSheet() {
  const { isOpen, close, messages, busy, currentScreen, execContext, sendMessage } = useCoach();
  const [input, setInput] = useState("");
  const bodyRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (isOpen) {
      setTimeout(() => textareaRef.current?.focus(), 450);
    }
  }, [isOpen]);

  useEffect(() => {
    bodyRef.current?.scrollTo({ top: bodyRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, busy]);

  function submit() {
    const text = input.trim();
    if (!text || busy) return;
    setInput("");
    sendMessage(text);
  }

  function handleKey(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  }

  function handleTextareaChange(e: React.ChangeEvent<HTMLTextAreaElement>) {
    setInput(e.target.value);
    // auto-grow
    e.target.style.height = "auto";
    e.target.style.height = `${Math.min(e.target.scrollHeight, 92)}px`;
  }

  const chips = getChips(currentScreen);

  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Scrim */}
          <motion.div
            className="coach-scrim"
            onClick={close}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.3 }}
          />

          {/* Sheet */}
          <motion.div
            className="coach-sheet"
            role="dialog"
            aria-label="Coach EasyHealth"
            initial={{ y: "102%" }}
            animate={{ y: 0 }}
            exit={{ y: "102%" }}
            transition={{ duration: 0.42, ease: [0.22, 1, 0.36, 1] }}
          >
            {/* Grabber */}
            <div className="coach-grabber" />

            {/* Header */}
            <div className="coach-head">
              <AgentOrb size="header" />
              <div className="coach-head-text">
                <span className="coach-head-title">Coach EasyHealth</span>
                <span className="coach-head-sub">
                  <span className="coach-status-dot" />
                  IA · responde em tempo real
                </span>
              </div>
              <button onClick={close} aria-label="Fechar chat" className="coach-close-btn">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            {/* Context badge (exec only) */}
            {currentScreen === "exec" && execContext && (
              <div className="coach-ctx-badge">
                <span className="coach-ctx-dot" />
                <span>
                  Em foco: <strong>{execContext.exerciseName}</strong>
                  {execContext.muscleGroup && <span style={{ color: "oklch(0.585 0.020 262)" }}> · {execContext.muscleGroup}</span>}
                  {execContext.setInfo && <span style={{ color: "oklch(0.585 0.020 262)" }}> · {execContext.setInfo}</span>}
                </span>
              </div>
            )}

            {/* Messages */}
            <div className="coach-body" ref={bodyRef}>
              {messages.map((msg) => (
                <MessageBubble key={msg.id} msg={msg} />
              ))}
              {busy && <TypingIndicator />}
            </div>

            {/* Quick chips */}
            <div className="coach-quick">
              {chips.map((chip) => (
                <button
                  key={chip.label}
                  className={`coach-chip${chip.swap ? " coach-chip--primary" : ""}`}
                  onClick={() => sendMessage(chip.text)}
                  disabled={busy}
                >
                  {chip.label}
                </button>
              ))}
            </div>

            {/* Input */}
            <div className="coach-input-bar">
              <textarea
                ref={textareaRef}
                value={input}
                onChange={handleTextareaChange}
                onKeyDown={handleKey}
                placeholder="Pergunte sobre o treino..."
                rows={1}
                className="coach-textarea"
                disabled={busy}
              />
              <button
                onClick={submit}
                disabled={!input.trim() || busy}
                aria-label="Enviar mensagem"
                className="coach-send-btn"
              >
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  width={38}
                  height={38}
                  aria-hidden
                >
                  <circle
                    cx="12" cy="12" r="12"
                    fill={(!input.trim() || busy)
                      ? "oklch(0.315 0.026 262)"
                      : "oklch(0.685 0.17 258)"}
                  />
                  <path
                    d="M8 12h8M13 8l4 4-4 4"
                    stroke="white"
                    strokeWidth={1.8}
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
