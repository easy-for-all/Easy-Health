"use client";

import { useEffect } from "react";
import Link from "next/link";
import { motion } from "framer-motion";
import { useAuth } from "@/features/auth/auth-context";
import { trackEvent, EVENTS } from "@/shared/lib/analytics";

export function TrialExpiredPaywall() {
  const { user } = useAuth();

  useEffect(() => {
    trackEvent(EVENTS.PAYWALL_VIEWED, { source: "trial_expired" });
    trackEvent(EVENTS.SCREEN_VIEW, { screen_name: "trial_expired_paywall" });
  }, []);

  const sessionsCount = 0;
  const plansCount = 0;

  return (
    <div className="min-h-[60vh] flex items-center justify-center px-4">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.35 }}
        className="max-w-sm w-full bg-white rounded-2xl border border-gray-200 p-8 text-center dark:bg-gray-900 dark:border-gray-800"
        style={{ boxShadow: "var(--shadow-elevated)" }}
      >
        <div className="w-16 h-16 bg-gradient-to-br from-amber-400 to-orange-500 rounded-full flex items-center justify-center mx-auto mb-5 shadow-md">
          <svg className="w-8 h-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>

        <span className="inline-block rounded-full bg-gray-100 dark:bg-gray-800 px-3 py-0.5 text-xs font-semibold text-gray-500 dark:text-gray-400 mb-3">
          Teste encerrado
        </span>

        <h2 className="text-xl font-bold text-gray-900 dark:text-gray-50 mb-2">
          Seu teste gratuito terminou
        </h2>

        <p className="text-gray-500 text-sm mb-1 leading-relaxed">
          Você explorou o EasyHealth durante 7 dias.{" "}
          {user?.name ? `Ótimo trabalho, ${user.name.split(" ")[0]}!` : ""}
        </p>
        <p className="text-gray-400 text-sm mb-6 leading-relaxed">
          Assine para continuar executando treinos, acompanhar progresso e receber evolução com IA.
        </p>

        <Link
          href="/billing"
          className="block w-full bg-primary-500 text-white rounded-xl py-3.5 text-sm font-semibold hover:bg-primary-600 transition-colors mb-3"
        >
          Ver planos e assinar →
        </Link>

        <Link
          href="/pricing"
          className="block text-sm text-gray-400 hover:text-gray-600 transition-colors"
        >
          Comparar planos
        </Link>
      </motion.div>
    </div>
  );
}
