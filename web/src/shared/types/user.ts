import type { BillingStatus } from "./subscription";

export type AccountType = "regular" | "personal_trainer";
export type ProfileVisibility = "private" | "public_limited" | "public";

export interface User {
  id: number;
  name: string;
  email: string;
  admin?: boolean;
  created_at: string;
  first_workout_completed_at?: string | null;
  avatar_url?: string | null;
  billing_status?: BillingStatus | null;
  account_type?: AccountType;
  profile_visibility?: ProfileVisibility;
  community_enabled?: boolean;
  referral_code?: string;
}

export interface PublicProfile {
  id: number;
  display_name: string;
  avatar_url?: string | null;
  public_bio?: string | null;
  profile_visibility: ProfileVisibility;
  account_type: AccountType;
  show_workout_count?: boolean;
  show_streak?: boolean;
  workout_count?: number | null;
}

export interface PublicProfileSettings {
  display_name?: string;
  avatar_visible: boolean;
  city_visible: boolean;
  country_visible: boolean;
  public_bio?: string | null;
  show_workout_count: boolean;
  show_streak: boolean;
  show_points: boolean;
  show_badges: boolean;
  preview?: PublicProfile;
}

export interface PrivacySettings {
  account_type: AccountType;
  profile_visibility: ProfileVisibility;
  community_enabled: boolean;
  marketing_consent: boolean;
  referral_code: string;
}

export interface SharedWorkout {
  id: number;
  token: string;
  title: string;
  visibility: "private_link" | "specific_users" | "community";
  include_weights: boolean;
  include_notes: boolean;
  expires_at?: string | null;
  view_count: number;
  exercise_count: number;
  share_url: string;
  created_at: string;
}

export interface SharedWorkoutPublic {
  id: number;
  title: string;
  shared_by: string;
  visibility: string;
  snapshot: {
    day_name: string;
    exercise_count: number;
    exercises: Array<{
      exercise_id: number;
      name: string;
      muscle_group: string;
      exercise_type: string;
      sets?: number;
      reps?: string;
      rest_seconds?: number;
      duration_minutes?: number;
      intensity?: string;
    }>;
    shared_at: string;
  };
  view_count: number;
  created_at: string;
}
