import { IconLock } from "../icons";

interface MedalProps {
  icon: string;
  name: string;
  desc?: string;
  earned?: boolean;
  progress?: number;
}

export function Medal({ icon, name, desc, earned = false, progress }: MedalProps) {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 6,
        padding: "14px 8px",
        borderRadius: "var(--r-md)",
        background: "var(--surface)",
        border: `1px solid ${earned ? "var(--primary-soft)" : "var(--border)"}`,
        position: "relative",
        opacity: earned ? 1 : 0.6,
        transition: "opacity .2s",
      }}
    >
      <span style={{ fontSize: 28, lineHeight: 1 }}>{icon}</span>

      {!earned && (
        <span
          style={{
            position: "absolute",
            top: 8,
            right: 8,
            color: "var(--text-dim)",
          }}
        >
          <IconLock className="w-3 h-3" />
        </span>
      )}

      <span
        style={{
          fontSize: 11,
          fontWeight: 700,
          textAlign: "center",
          color: earned ? "var(--text)" : "var(--text-dim)",
          lineHeight: 1.2,
        }}
      >
        {name}
      </span>

      {!earned && progress != null && (
        <div
          style={{
            width: "100%",
            height: 3,
            background: "var(--surface-3)",
            borderRadius: 2,
            overflow: "hidden",
          }}
        >
          <div
            style={{
              width: `${Math.min(100, progress)}%`,
              height: "100%",
              background: "var(--primary)",
              transition: "width .5s var(--ease)",
            }}
          />
        </div>
      )}

      {desc && (
        <span style={{ fontSize: 10, color: "var(--text-faint)", textAlign: "center", lineHeight: 1.3 }}>
          {desc}
        </span>
      )}
    </div>
  );
}
