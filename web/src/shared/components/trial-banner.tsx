"use client";

import Link from "next/link";
import { useSubscription } from "@/features/billing/use-subscription";

export function TrialBanner() {
  const { trialActive, trialDaysRemaining, canAccessPremiumFeatures } = useSubscription();

  if (!trialActive || canAccessPremiumFeatures) return null;

  if (trialDaysRemaining <= 1) {
    return (
      <div className="w-full bg-red-500 text-white px-4 py-2 flex items-center justify-between text-sm">
        <span className="font-medium">
          {trialDaysRemaining === 0
            ? "Seu teste grátis termina hoje!"
            : "Último dia do seu teste grátis!"}
        </span>
        <Link
          href="/billing"
          className="ml-3 shrink-0 rounded-lg bg-white px-3 py-1 text-xs font-semibold text-red-600 hover:bg-red-50 transition-colors"
        >
          Assinar agora
        </Link>
      </div>
    );
  }

  if (trialDaysRemaining <= 3) {
    return (
      <div className="w-full bg-amber-400 text-amber-900 px-4 py-2 flex items-center justify-between text-sm">
        <span className="font-medium">
          Restam <strong>{trialDaysRemaining} dias</strong> do seu teste grátis.
        </span>
        <Link
          href="/billing"
          className="ml-3 shrink-0 rounded-lg bg-amber-900 px-3 py-1 text-xs font-semibold text-white hover:bg-amber-800 transition-colors"
        >
          Assinar agora
        </Link>
      </div>
    );
  }

  return (
    <div className="w-full bg-primary-50 border-b border-primary-100 text-primary-800 px-4 py-2 flex items-center justify-between text-sm dark:bg-primary-950 dark:border-primary-900 dark:text-primary-200">
      <span>
        Teste grátis · <strong>{trialDaysRemaining} dias</strong> restantes
      </span>
      <Link
        href="/billing"
        className="ml-3 shrink-0 text-xs font-semibold text-primary-600 hover:text-primary-800 dark:text-primary-400 transition-colors"
      >
        Assinar →
      </Link>
    </div>
  );
}
