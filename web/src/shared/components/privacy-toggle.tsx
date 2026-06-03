"use client";

interface PrivacyToggleProps {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  description?: string;
  disabled?: boolean;
}

export function PrivacyToggle({ checked, onChange, label, description, disabled }: PrivacyToggleProps) {
  return (
    <label className={`flex items-start justify-between gap-3 py-3 ${disabled ? "opacity-50 cursor-not-allowed" : "cursor-pointer"}`}>
      <div className="flex-1">
        <span className="block text-sm font-medium text-gray-900 dark:text-gray-100">{label}</span>
        {description && (
          <span className="block text-xs text-gray-500 dark:text-gray-400 mt-0.5">{description}</span>
        )}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => !disabled && onChange(!checked)}
        className={`relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 ${
          checked ? "bg-primary-500" : "bg-gray-200 dark:bg-gray-700"
        }`}
      >
        <span
          className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
            checked ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
    </label>
  );
}
