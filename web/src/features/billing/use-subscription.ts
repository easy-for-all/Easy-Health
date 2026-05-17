"use client";

import { useAuth } from "@/features/auth/auth-context";

export function useSubscription() {
  const { user } = useAuth();
  const bs = user?.billing_status ?? null;

  const isProUser = bs?.paid === true;
  const isBillingActive = bs?.status === "active" || bs?.status === "trialing";
  const canAccessPremiumFeatures = isProUser && isBillingActive;
  const isTrialing = bs?.status === "trialing";
  const hasNoPlan = !bs || bs.plan === "none" || bs.plan === null;

  return {
    billingStatus: bs,
    isProUser,
    isBillingActive,
    canAccessPremiumFeatures,
    isTrialing,
    hasNoPlan,
  };
}
