import "./ui.css";

export function SliderRow({ label, unit, value, min, max, step = 1, onChange }: {
  label: string;
  unit?: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (value: number) => void;
}) {
  return (
    <div className="slide-row">
      <div className="lab">
        <span>{label}</span>
        <b>{value}{unit && <em>{unit}</em>}</b>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <div className="ends">
        <span>{min}{unit}</span>
        <span>{max}{unit}</span>
      </div>
    </div>
  );
}
