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
  const freeWorkoutUsed = bs?.free_workout_used === true;

  // App-level trial (no credit card required)
  const trialActive = bs?.app_trial_active === true;
  const trialDaysRemaining = bs?.app_trial_days_remaining ?? 0;
  const trialEndsAt = bs?.app_trial_ends_at ?? null;
  const accessLocked = bs?.access_locked === true;

  // Full access = premium subscription OR app trial active
  const hasActiveAccess = canAccessPremiumFeatures || trialActive;
  const canAccessWorkout = hasActiveAccess;

  return {
    billingStatus: bs,
    isProUser,
    isBillingActive,
    canAccessPremiumFeatures,
    isTrialing,
    hasNoPlan,
    freeWorkoutUsed,
    canAccessWorkout,
    trialActive,
    trialDaysRemaining,
    trialEndsAt,
    accessLocked,
    hasActiveAccess,
  };
}
