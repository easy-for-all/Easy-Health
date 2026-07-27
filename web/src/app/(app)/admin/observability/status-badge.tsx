import { CheckStatus } from "./types";

// Grey is not "fine" — it means we could not measure. The label says so
// explicitly rather than leaving the colour to imply it.
const STATUS_STYLE: Record<CheckStatus, string> = {
  healthy: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300",
  warning: "bg-amber-100 text-amber-700 dark:bg-amber-900 dark:text-amber-300",
  critical: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300",
  insufficient_data: "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300",
};

const STATUS_LABEL: Record<CheckStatus, string> = {
  healthy: "Saudável",
  warning: "Atenção",
  critical: "Crítico",
  insufficient_data: "Sem amostra",
};

export function statusLabel(status: CheckStatus): string {
  return STATUS_LABEL[status] ?? status;
}

export function StatusBadge({ status }: { status: CheckStatus }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_STYLE[status] ?? STATUS_STYLE.insufficient_data}`}
      // The colour alone must not be the only carrier of meaning.
      role="status"
    >
      {statusLabel(status)}
    </span>
  );
}
