"use client";

import { useEffect } from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { useSubscription } from "@/features/billing/use-subscription";
import { GlowPulse } from "./motion";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";

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
  useEffect(() => {
    trackEvent(EVENTS.PAYWALL_VIEWED);
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "paywall" });
  }, []);

  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.35 }}
        className="max-w-sm w-full bg-white rounded-2xl border border-gray-200 p-8 text-center dark:bg-gray-900 dark:border-gray-800"
        style={{ boxShadow: "var(--shadow-elevated)" }}
      >
        <motion.div
          whileHover={{ scale: 1.08 }}
          transition={{ type: "spring", stiffness: 400 }}
          className="w-16 h-16 bg-gradient-to-br from-primary-400 to-primary-600 rounded-full flex items-center justify-center mx-auto mb-5 shadow-md"
        >
          <svg className="w-8 h-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>
        </motion.div>

        <span className="inline-block rounded-full bg-gradient-to-r from-yellow-400 to-yellow-500 px-3 py-0.5 text-xs font-bold text-white mb-3">
          PRO
        </span>

        <h2 className="text-xl font-bold text-gray-900 dark:text-gray-50 mb-2">
          Eleve seus treinos ao próximo nível
        </h2>
        <p className="text-gray-500 text-sm mb-6 leading-relaxed">
          Planos personalizados por IA, histórico ilimitado, análise de progressão e muito mais. Experimente 7 dias grátis.
        </p>

        <GlowPulse color="blue" radius={12} className="w-full mb-3">
          <Link
            href="/billing"
            className="block w-full bg-primary-500 text-white rounded-xl py-3.5 text-sm font-semibold hover:bg-primary-600 transition-colors"
          >
            Começar 7 dias grátis →
          </Link>
        </GlowPulse>

        <Link
          href="/pricing"
          className="block text-sm text-gray-400 hover:text-gray-600 transition-colors"
        >
          Ver todos os planos
        </Link>
      </motion.div>
    </div>
  );
}
