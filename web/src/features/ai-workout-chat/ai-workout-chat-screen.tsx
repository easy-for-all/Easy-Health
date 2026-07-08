"use client";

import { useEffect, useRef, useState } from "react";
import { AgentOrb } from "@/shared/components/agent-orb";
import { useAiWorkoutChat } from "./use-ai-workout-chat";
import { AiWorkoutMessageBubble } from "./ai-workout-message-bubble";
import { AiWorkoutQuickChips } from "./ai-workout-quick-chips";
import { AiWorkoutChatInput } from "./ai-workout-chat-input";
import { AiWorkoutPreviewCard } from "./ai-workout-preview-card";
import { AI_CHAT_COLORS } from "./theme";
import "@/shared/components/coach-sheet/coach-sheet.css";

interface Props {
  onConfirmed: (workoutPlanId: number) => void;
  onBack: () => void;
}

export function AiWorkoutChatScreen({ onConfirmed, onBack }: Props) {
  const { phase, messages, preview, busy, error, workoutPlanId, start, sendMessage, confirm } = useAiWorkoutChat();
  const [input, setInput] = useState("");
  const bodyRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    start();
  }, [start]);

  useEffect(() => {
    bodyRef.current?.scrollTo({ top: bodyRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, busy, preview]);

  useEffect(() => {
    if (phase === "confirmed" && workoutPlanId) onConfirmed(workoutPlanId);
  }, [phase, workoutPlanId, onConfirmed]);

  function handleSend(text?: string) {
    const value = (text ?? input).trim();
    if (!value || busy) return;
    setInput("");
    sendMessage(value);
  }

  const inputDisabled = busy || phase === "starting" || phase === "error" || phase === "confirming" || phase === "confirmed";

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 40, display: "flex", flexDirection: "column", background: AI_CHAT_COLORS.bg }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "max(14px, env(safe-area-inset-top, 14px)) 16px 12px", flexShrink: 0 }}>
        <button
          onClick={onBack}
          aria-label="Voltar"
          style={{
            width: 34, height: 34, borderRadius: "50%", border: `1px solid ${AI_CHAT_COLORS.border}`, background: "transparent",
            color: AI_CHAT_COLORS.textDim, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", flexShrink: 0,
          }}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} width={16} height={16}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 18l-6-6 6-6" />
          </svg>
        </button>
        <AgentOrb size="header" />
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 }}>
          <span style={{ fontSize: 17, fontWeight: 700, color: AI_CHAT_COLORS.text, letterSpacing: "-0.01em" }}>Criar treino com IA</span>
          <span style={{ fontSize: 12, color: AI_CHAT_COLORS.textDim }}>
            Conte sua rotina, objetivo e limitações. A EasyHealth monta um treino para você.
          </span>
        </div>
      </div>

      {/* Messages */}
      <div className="coach-body" ref={bodyRef} style={{ flex: 1 }}>
        {messages.map((msg, i) => (
          <AiWorkoutMessageBubble key={i} message={msg} />
        ))}
        {busy && (
          <div className="coach-msg coach-msg--ai">
            <AgentOrb size="avatar" pulse />
            <div className="coach-bubble coach-bubble--ai">
              <span className="coach-dots"><span /><span /><span /></span>
            </div>
          </div>
        )}
        {preview && (phase === "previewing" || phase === "confirming") && (
          <AiWorkoutPreviewCard
            preview={preview}
            confirming={phase === "confirming"}
            onAdjust={() => textareaRef.current?.focus()}
            onConfirm={confirm}
          />
        )}
      </div>

      {error && (
        <p style={{ margin: "0 16px 8px", fontSize: 12.5, color: AI_CHAT_COLORS.danger }}>
          {error}
          {phase === "error" && (
            <button
              onClick={() => start()}
              style={{ marginLeft: 8, background: "none", border: "none", color: AI_CHAT_COLORS.primary, fontWeight: 700, cursor: "pointer", fontSize: 12.5 }}
            >
              Tentar novamente
            </button>
          )}
        </p>
      )}

      {phase !== "confirmed" && (
        <>
          <AiWorkoutQuickChips onSelect={(text) => handleSend(text)} disabled={inputDisabled} />
          <AiWorkoutChatInput
            value={input}
            onChange={setInput}
            onSubmit={() => handleSend()}
            disabled={inputDisabled}
            textareaRef={textareaRef}
          />
        </>
      )}
    </div>
  );
}
