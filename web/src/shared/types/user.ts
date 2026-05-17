import type { BillingStatus } from "./subscription";

export interface User {
  id: number;
  name: string;
  email: string;
  created_at: string;
  avatar_url?: string | null;
  billing_status?: BillingStatus | null;
}
