import "./ui.css";

type ProgressDotsProps = {
  total: number;
  current: number; // 0-indexed current step
};

export function ProgressDots({ total, current }: ProgressDotsProps) {
  return (
    <div className="progress-dots" role="progressbar" aria-valuenow={current + 1} aria-valuemax={total}>
      {Array.from({ length: total }, (_, i) => {
        const cls = i < current ? "on" : i === current ? "cur" : "";
        return <i key={i} className={cls} aria-hidden />;
      })}
    </div>
  );
}
