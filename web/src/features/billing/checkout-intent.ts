const KEY = "eh_pending_plan";

export type PendingPlan = "pro_monthly" | "pro_yearly";

export function setPendingPlan(plan: PendingPlan): void {
  try {
    sessionStorage.setItem(KEY, plan);
  } catch {
    // sessionStorage not available (SSR)
  }
}

export function getPendingPlan(): PendingPlan | null {
  try {
    const val = sessionStorage.getItem(KEY);
    if (val === "pro_monthly" || val === "pro_yearly") return val;
  } catch {
    // sessionStorage not available (SSR)
  }
  return null;
}

export function clearPendingPlan(): void {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    // sessionStorage not available (SSR)
  }
}
