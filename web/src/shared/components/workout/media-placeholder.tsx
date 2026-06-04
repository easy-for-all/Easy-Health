import "./workout-ui.css";

type MediaPlaceholderProps = {
  label?: string;
  className?: string;
  style?: React.CSSProperties;
};

export function MediaPlaceholder({ label = "mídia do exercício", className = "", style }: MediaPlaceholderProps) {
  return (
    <div className={`media-ph ${className}`} style={style}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round" style={{ width: 26, height: 26, stroke: "var(--text-faint)" }}>
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <circle cx="8.5" cy="8.5" r="1.5" />
        <polyline points="21 15 16 10 5 21" />
      </svg>
      <span className="mph-label">{label}</span>
    </div>
  );
}
