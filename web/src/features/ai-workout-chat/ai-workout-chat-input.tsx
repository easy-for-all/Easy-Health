"use client";

import type { RefObject } from "react";

const MAX_LENGTH = 1500;

interface Props {
  value: string;
  onChange: (value: string) => void;
  onSubmit: () => void;
  disabled?: boolean;
  textareaRef?: RefObject<HTMLTextAreaElement | null>;
}

export function AiWorkoutChatInput({ value, onChange, onSubmit, disabled, textareaRef }: Props) {
  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      onSubmit();
    }
  }

  function handleChange(e: React.ChangeEvent<HTMLTextAreaElement>) {
    onChange(e.target.value.slice(0, MAX_LENGTH));
    e.target.style.height = "auto";
    e.target.style.height = `${Math.min(e.target.scrollHeight, 92)}px`;
  }

  return (
    <div className="coach-input-bar">
      <textarea
        ref={textareaRef}
        value={value}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder="Ex: quero treinar 4x por semana, foco em hipertrofia, tenho 40 minutos e sinto dor no joelho."
        rows={1}
        maxLength={MAX_LENGTH}
        className="coach-textarea"
        disabled={disabled}
      />
      <button
        onClick={onSubmit}
        disabled={!value.trim() || disabled}
        aria-label="Enviar mensagem"
        className="coach-send-btn"
      >
        <svg viewBox="0 0 24 24" fill="none" width={38} height={38} aria-hidden>
          <circle
            cx="12" cy="12" r="12"
            fill={(!value.trim() || disabled) ? "oklch(0.315 0.026 262)" : "oklch(0.685 0.17 258)"}
          />
          <path d="M8 12h8M13 8l4 4-4 4" stroke="white" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
    </div>
  );
}
