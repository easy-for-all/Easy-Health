"use client";

import { useEffect, useRef, useState } from "react";

type RenameWorkoutModalProps = {
  open: boolean;
  currentName: string;
  defaultName: string;
  onSave: (name: string) => Promise<void>;
  onClose: () => void;
};

export function RenameWorkoutModal({ open, currentName, defaultName, onSave, onClose }: RenameWorkoutModalProps) {
  const [value, setValue] = useState(currentName);
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setValue(currentName);
      setTimeout(() => inputRef.current?.focus(), 80);
    }
  }, [open, currentName]);

  if (!open) return null;

  async function handleSave() {
    setSaving(true);
    try {
      await onSave(value.trim());
      onClose();
    } finally {
      setSaving(false);
    }
  }

  function handleKey(e: React.KeyboardEvent) {
    if (e.key === "Enter") handleSave();
    if (e.key === "Escape") onClose();
  }

  return (
    <div
      style={{
        position: "fixed", inset: 0, zIndex: 999,
        background: "oklch(0 0 0 / 0.6)",
        display: "flex", alignItems: "flex-end", justifyContent: "center",
      }}
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        style={{
          width: "100%", maxWidth: 480,
          background: "var(--surface-2, var(--surface))",
          borderRadius: "var(--r-lg) var(--r-lg) 0 0",
          padding: "24px 20px 40px",
          boxShadow: "0 -4px 32px oklch(0 0 0 / 0.4)",
        }}
      >
        <p style={{ fontWeight: 700, fontSize: 17, margin: "0 0 16px" }}>Renomear treino</p>
        <input
          ref={inputRef}
          type="text"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={handleKey}
          placeholder={defaultName}
          maxLength={60}
          style={{
            width: "100%", boxSizing: "border-box",
            background: "var(--surface)", border: "1.5px solid var(--border)",
            borderRadius: "var(--r-md, 12px)", padding: "12px 14px",
            fontSize: 15, color: "var(--text)", outline: "none",
          }}
        />
        <p style={{ fontSize: 12, color: "var(--text-dim)", margin: "6px 0 20px" }}>
          Deixe em branco para usar o nome padrão ({defaultName})
        </p>
        <div style={{ display: "flex", gap: 10 }}>
          <button
            onClick={onClose}
            style={{
              flex: 1, borderRadius: "var(--r-pill)", padding: "13px",
              background: "var(--surface)", border: "1px solid var(--border)",
              color: "var(--text)", fontWeight: 600, fontSize: 15, cursor: "pointer",
            }}
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            style={{
              flex: 2, borderRadius: "var(--r-pill)", padding: "13px",
              background: "linear-gradient(180deg, var(--primary), var(--primary-2))",
              color: "var(--on-primary)", fontWeight: 700, fontSize: 15,
              border: 0, cursor: saving ? "not-allowed" : "pointer",
              opacity: saving ? 0.7 : 1,
            }}
          >
            {saving ? "Salvando…" : "Salvar"}
          </button>
        </div>
      </div>
    </div>
  );
}
