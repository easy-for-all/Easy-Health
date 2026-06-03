export interface ClientPermissions {
  can_view_assigned_workouts: boolean;
  can_view_completed_workouts: boolean;
  can_view_adherence: boolean;
  can_view_exercise_performance: boolean;
  can_view_body_weight: boolean;
  can_view_photos: boolean;
  can_view_body_analysis: boolean;
  can_view_exams: boolean;
}

export interface ClientSummary {
  relationship_id: number;
  client_id: number;
  name: string;
  avatar_url?: string | null;
  status: "invited" | "active" | "paused" | "removed";
  started_at?: string | null;
  weekly_adherence?: number | null;
  last_session_at?: string | null;
  days_without_training?: number | null;
  inactive_alert: boolean;
  needs_new_plan: boolean;
  has_active_plan: boolean;
}

export interface ClientDetail extends ClientSummary {
  permissions: ClientPermissions;
  adherence?: {
    weekly_adherence?: number | null;
    last_session_at?: string | null;
    days_without_training?: number | null;
    inactive_alert: boolean;
    needs_new_plan: boolean;
  } | null;
  recent_sessions?: Array<{
    id: number;
    completed_at: string;
    duration?: number | null;
  }>;
}

export interface PersonalDashboard {
  active_clients: number;
  inactive_7_days: number;
  high_adherence: number;
  needs_new_plan: number;
  pending_invites: number;
}

export interface InvitationResult {
  invitation_code: string;
  invite_url: string;
  expires_at: string;
}
