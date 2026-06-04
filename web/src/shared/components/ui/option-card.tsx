import "./ui.css";

type OptionCardProps = {
  icon?: React.ReactNode;
  label: string;
  description?: string;
  selected?: boolean;
  onClick: () => void;
  className?: string;
};

export function OptionCard({ icon, label, description, selected, onClick, className = "" }: OptionCardProps) {
  return (
    <button
      className={`opt${selected ? " sel" : ""} ${className}`}
      onClick={onClick}
      type="button"
    >
      {icon && (
        <span className="oicon" aria-hidden>
          {typeof icon === "string" ? <span style={{ fontSize: 20 }}>{icon}</span> : icon}
        </span>
      )}
      <span className="otxt">
        <b>{label}</b>
        {description && <small>{description}</small>}
      </span>
      <span className="chk" aria-hidden>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round">
          <path d="M20 6L9 17l-5-5" />
        </svg>
      </span>
    </button>
  );
}
