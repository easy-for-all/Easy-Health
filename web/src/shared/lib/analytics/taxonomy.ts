// AUTO-MIRRORED from api/config/analytics/events.yml (single source of truth).
// A parity spec (analytics-taxonomy.test.ts) fails if this drifts from the YAML.
// Do not edit by hand without updating events.yml.

export const TAXONOMY_VERSION = 1;

export type Sink = "server" | "ga4" | "clarity";

export const EVENT_SINKS = {
  app_install_attributed: ["server"] as Sink[],
  app_first_open: ["server","ga4"] as Sink[],
  app_opened: ["server","ga4"] as Sink[],
  app_backgrounded: ["ga4"] as Sink[],
  app_resumed: ["ga4"] as Sink[],
  app_updated: ["server","ga4"] as Sink[],
  session_started: ["server","ga4"] as Sink[],
  session_ended: ["ga4"] as Sink[],
  screen_view: ["ga4"] as Sink[],
  web_session_started: ["server","ga4"] as Sink[],
  pwa_installed: ["server","ga4"] as Sink[],
  pwa_opened: ["ga4"] as Sink[],
  deep_link_opened: ["server","ga4"] as Sink[],
  landing_page_viewed: ["ga4","clarity"] as Sink[],
  signup_started: ["ga4"] as Sink[],
  signup_completed: ["server","ga4"] as Sink[],
  login_started: ["ga4"] as Sink[],
  login_completed: ["server","ga4"] as Sink[],
  login_failed: ["ga4"] as Sink[],
  logout_completed: ["ga4"] as Sink[],
  social_login_started: ["ga4"] as Sink[],
  social_login_completed: ["server","ga4"] as Sink[],
  social_login_failed: ["ga4"] as Sink[],
  onboarding_started: ["server","ga4"] as Sink[],
  onboarding_flow_selected: ["server","ga4"] as Sink[],
  onboarding_step_viewed: ["ga4"] as Sink[],
  onboarding_step_completed: ["server","ga4"] as Sink[],
  onboarding_step_skipped: ["ga4"] as Sink[],
  onboarding_abandoned: ["server","ga4","clarity"] as Sink[],
  onboarding_completed: ["server","ga4"] as Sink[],
  workout_created: ["server","ga4","clarity"] as Sink[],
  workout_viewed: ["server","ga4","clarity"] as Sink[],
  workout_details_viewed: ["ga4"] as Sink[],
  workout_start_clicked: ["server","ga4","clarity"] as Sink[],
  workout_started: ["server","ga4","clarity"] as Sink[],
  workout_first_exercise_started: ["server","ga4"] as Sink[],
  workout_exercise_completed: ["ga4"] as Sink[],
  workout_abandoned: ["server","ga4","clarity"] as Sink[],
  workout_completed: ["server","ga4"] as Sink[],
  workout_repeated: ["server","ga4"] as Sink[],
  workout_edited: ["ga4"] as Sink[],
  exercise_replaced: ["ga4"] as Sink[],
  workout_favorited: ["ga4"] as Sink[],
  home_viewed: ["ga4"] as Sink[],
  plan_viewed: ["ga4"] as Sink[],
  progress_viewed: ["ga4"] as Sink[],
  profile_viewed: ["ga4"] as Sink[],
  quick_workout_started: ["server","ga4"] as Sink[],
  complete_workout_started: ["server","ga4"] as Sink[],
  photo_ai_started: ["ga4"] as Sink[],
  ai_conversation_started: ["ga4"] as Sink[],
  coach_message_sent: ["ga4"] as Sink[],
  coach_suggestion_accepted: ["ga4"] as Sink[],
  coach_suggestion_rejected: ["ga4"] as Sink[],
  progressive_profile_shown: ["ga4"] as Sink[],
  progressive_profile_answered: ["ga4"] as Sink[],
  progressive_profile_skipped: ["ga4"] as Sink[],
  push_permission_prompted: ["server","ga4"] as Sink[],
  push_permission_granted: ["server","ga4"] as Sink[],
  push_permission_denied: ["server","ga4"] as Sink[],
  push_permission_later: ["ga4"] as Sink[],
  push_token_registered: ["server"] as Sink[],
  push_scheduled: ["server"] as Sink[],
  push_sent: ["server"] as Sink[],
  push_delivered: ["server"] as Sink[],
  push_opened: ["server","ga4"] as Sink[],
  push_deep_link_resolved: ["server"] as Sink[],
  push_failed: ["server"] as Sink[],
  push_disabled: ["server","ga4"] as Sink[],
  workout_started_after_push: ["server"] as Sink[],
  workout_completed_after_push: ["server"] as Sink[],
  paywall_viewed: ["server","ga4","clarity"] as Sink[],
  checkout_started: ["server","ga4"] as Sink[],
  checkout_session_created: ["server"] as Sink[],
  checkout_failed: ["server","ga4"] as Sink[],
  checkout_redirect_opened: ["server","ga4"] as Sink[],
  checkout_completed: ["server","ga4"] as Sink[],
  subscription_started: ["server","ga4"] as Sink[],
  subscription_renewed: ["server"] as Sink[],
  subscription_canceled: ["server","ga4"] as Sink[],
  trial_started: ["server","ga4"] as Sink[],
  trial_expired: ["server","ga4"] as Sink[],
  experiment_assigned: ["server"] as Sink[],
  experiment_exposed: ["server","ga4"] as Sink[],
  experiment_converted: ["server","ga4"] as Sink[],
  analytics_event_rejected: ["server"] as Sink[],
  deep_link_failed: ["server","ga4"] as Sink[],
  workout_load_failed: ["server","ga4"] as Sink[],
  workout_save_failed: ["server","ga4"] as Sink[],
  push_registration_failed: ["server","ga4"] as Sink[],
} as const;

export type EventName = keyof typeof EVENT_SINKS;

export const ALL_EVENTS = Object.keys(EVENT_SINKS) as EventName[];

function namesForSink(sink: Sink): EventName[] {
  return (Object.keys(EVENT_SINKS) as EventName[]).filter((n) =>
    (EVENT_SINKS[n] as readonly Sink[]).includes(sink)
  );
}

// Explicit routing catalogs (mirrors the backend Analytics::EventCatalog).
export const SERVER_TRACKED_EVENTS = namesForSink("server");
export const GA4_TRACKED_EVENTS = namesForSink("ga4");
export const CLARITY_CUSTOM_TAG_EVENTS = namesForSink("clarity");

export function isKnownEvent(name: string): name is EventName {
  return name in EVENT_SINKS;
}
export function sinksFor(name: EventName): readonly Sink[] {
  return EVENT_SINKS[name];
}
