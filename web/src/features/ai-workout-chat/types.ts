export type WorkoutChatRole = "user" | "assistant";

export type WorkoutChatBlockReason = "security_abuse" | "out_of_scope";

export interface WorkoutChatMessage {
  role: WorkoutChatRole;
  content: string;
  blocked?: boolean;
  blockReason?: WorkoutChatBlockReason;
}

export interface WorkoutChatPreviewDay {
  name: string;
  muscle_groups: string[];
}

export interface WorkoutChatPreview {
  training_method: string;
  plan_name: string;
  rationale: string;
  week_structure: WorkoutChatPreviewDay[];
  sets_reps: { sets: number; reps: number; rest_seconds: number };
  progression_strategy: string;
  safety_notes: string[];
}

export type WorkoutChatConversationStatus = "collecting" | "previewing" | "confirmed";
