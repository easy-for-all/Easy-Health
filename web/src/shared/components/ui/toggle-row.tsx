"use client";

interface ToggleRowProps {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  hint?: string;
  locked?: boolean;
  "aria-label"?: string;
}

export function ToggleRow({ checked, onChange, label, hint, locked = false, "aria-label": ariaLabel }: ToggleRowProps) {
  const handleClick = () => {
    if (!locked) onChange(!checked);
  };

  return (
    <label
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "13px 0",
        cursor: locked ? "not-allowed" : "pointer",
        opacity: locked ? 0.45 : 1,
        transition: "opacity .2s",
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: "block", fontSize: 14, fontWeight: 500, color: "var(--text)" }}>
          {label}
        </span>
        {hint && (
          <span style={{ display: "block", fontSize: 12, color: "var(--text-dim)", marginTop: 2 }}>
            {hint}
          </span>
        )}
      </div>

      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={ariaLabel ?? label}
        disabled={locked}
        onClick={handleClick}
        style={{
          position: "relative",
          display: "inline-flex",
          flexShrink: 0,
          width: 44,
          height: 26,
          borderRadius: "var(--r-pill)",
          border: "2px solid transparent",
          background: checked ? "var(--primary)" : "var(--surface-3)",
          transition: "background .2s var(--ease)",
          cursor: locked ? "not-allowed" : "pointer",
          outline: "none",
        }}
        onKeyDown={(e) => {
          if (e.key === " " || e.key === "Enter") {
            e.preventDefault();
            handleClick();
          }
        }}
      >
        <span
          style={{
            display: "block",
            width: 18,
            height: 18,
            borderRadius: "50%",
            background: "#fff",
            boxShadow: "0 1px 3px rgba(0,0,0,.3)",
            position: "absolute",
            top: 2,
            left: checked ? 18 : 2,
            transition: "left .2s var(--ease)",
          }}
        />
      </button>
    </label>
  );
}
