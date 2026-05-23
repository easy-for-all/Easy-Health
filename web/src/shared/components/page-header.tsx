import type { ReactNode } from "react";

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  action?: ReactNode;
  onBack?: () => void;
  backLabel?: string;
}

export function PageHeader({ title, subtitle, action, onBack, backLabel = "← Voltar" }: PageHeaderProps) {
  return (
    <header className="mb-6">
      {onBack && (
        <button
          onClick={onBack}
          className="mb-3 text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
        >
          {backLabel}
        </button>
      )}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-gray-50">{title}</h1>
          {subtitle && <p className="mt-0.5 text-sm text-gray-500 dark:text-gray-400">{subtitle}</p>}
        </div>
        {action && <div>{action}</div>}
      </div>
    </header>
  );
}
