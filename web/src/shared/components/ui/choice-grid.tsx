import "./ui.css";

export function ChoiceGrid<T extends string>({ values, selected, onToggle, limit }: {
  values: { value: T; label: string }[];
  selected: T[];
  onToggle: (value: T) => void;
  limit?: number;
}) {
  return (
    <div className="opt-grid">
      {values.map((item) => {
        const active = selected.includes(item.value);
        const blocked = !active && !!limit && selected.length >= limit;
        return (
          <button key={item.value} type="button" disabled={blocked} className={`opt${active ? " sel" : ""}`} onClick={() => onToggle(item.value)}>
            <span className="otxt"><b>{item.label}</b></span>
          </button>
        );
      })}
    </div>
  );
}
