export type PlanName = "none" | "pro_monthly" | "pro_yearly";
export type SubscriptionStatus =
  | "none"
  | "trialing"
  | "active"
  | "past_due"
  | "canceled"
  | "unpaid"
  | "incomplete";

export interface BillingStatus {
  plan: PlanName | null;
  status: SubscriptionStatus | null;
  paid: boolean;
  trial_end: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  stripe_customer_id: string | null;
}
