"use client";

import { useState, useRef } from "react";
import { motion } from "framer-motion";
import { IconSend } from "../icons";

interface CommentBoxProps {
  placeholder?: string;
  onSubmit: (text: string) => Promise<void> | void;
  submitLabel?: string;
}

export function CommentBox({ placeholder = "Adicionar observação...", onSubmit, submitLabel = "Enviar" }: CommentBoxProps) {
  const [text, setText] = useState("");
  const [loading, setLoading] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const resize = () => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  };

  const handleSubmit = async () => {
    if (!text.trim() || loading) return;
    setLoading(true);
    try {
      await onSubmit(text.trim());
      setText("");
      if (textareaRef.current) {
        textareaRef.current.style.height = "auto";
      }
    } finally {
      setLoading(false);
    }
  };

  const canSend = text.trim().length > 0 && !loading;

  return (
    <div
      style={{
        display: "flex",
        gap: 10,
        padding: "12px",
        background: "var(--surface)",
        border: "1px solid var(--border)",
        borderRadius: "var(--r-md)",
        alignItems: "flex-end",
      }}
    >
      <textarea
        ref={textareaRef}
        value={text}
        onChange={(e) => {
          setText(e.target.value);
          resize();
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) handleSubmit();
        }}
        placeholder={placeholder}
        rows={1}
        style={{
          flex: 1,
          resize: "none",
          border: "none",
          outline: "none",
          background: "transparent",
          color: "var(--text)",
          fontSize: 14,
          lineHeight: 1.5,
          fontFamily: "var(--font-body)",
          minHeight: 44,
          padding: "10px 0",
          overflowY: "hidden",
        }}
        aria-label="Campo de observação"
      />

      <motion.button
        onClick={handleSubmit}
        disabled={!canSend}
        aria-label={submitLabel}
        whileTap={canSend ? { scale: 0.9 } : {}}
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: 40,
          height: 40,
          borderRadius: "var(--r-sm)",
          background: canSend ? "var(--primary)" : "var(--surface-3)",
          color: canSend ? "var(--on-primary)" : "var(--text-dim)",
          border: "none",
          cursor: canSend ? "pointer" : "not-allowed",
          flexShrink: 0,
          transition: "background .18s, color .18s",
        }}
      >
        <IconSend className="w-4 h-4" />
      </motion.button>
    </div>
  );
}
