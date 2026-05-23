"use client";

import Link from "next/link";
import { useSubscription } from "@/features/billing/use-subscription";

interface UpgradeGateProps {
  children: React.ReactNode;
  allowFreeWorkout?: boolean;
}

export function UpgradeGate({ children, allowFreeWorkout }: UpgradeGateProps) {
  const { canAccessPremiumFeatures, canAccessWorkout } = useSubscription();
  const canAccess = allowFreeWorkout ? canAccessWorkout : canAccessPremiumFeatures;

  if (!canAccess) {
    return <UpgradeBanner />;
  }

  return <>{children}</>;
}

export function UpgradeBanner() {
  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <div className="max-w-sm w-full bg-white rounded-2xl border border-gray-200 p-8 text-center shadow-sm">
        <div className="w-14 h-14 bg-primary-50 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-7 h-7 text-primary-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
        </div>

        <h2 className="text-lg font-bold text-gray-900 mb-2">
          Acesso exclusivo para assinantes Pro
        </h2>
        <p className="text-gray-500 text-sm mb-6">
          Assine o plano Pro e desbloqueie treinos personalizados, histórico ilimitado e muito mais. Comece com 7 dias grátis.
        </p>

        <Link
          href="/billing"
          className="block w-full bg-primary-500 text-white rounded-xl py-3 text-sm font-semibold hover:bg-primary-600 transition mb-3"
        >
          Ver planos — 7 dias grátis
        </Link>

        <Link
          href="/pricing"
          className="block text-sm text-gray-400 hover:underline"
        >
          Saiba mais sobre os planos
        </Link>
      </div>
    </div>
  );
}
