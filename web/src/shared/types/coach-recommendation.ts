export interface CoachRecommendationExercise {
  id: number;
  name: string;
}

export interface CoachRecommendationAction {
  label: string;
  action: "accept" | "dismiss";
}

export interface CoachRecommendation {
  id: number;
  type: string;
  status: "pending" | "accepted" | "dismissed" | "expired";
  title: string;
  message: string;
  exercise: CoachRecommendationExercise | null;
  current_value: number | null;
  recommended_value: number | null;
  unit: string;
  confidence: number | null;
  reasons: string[];
  actions: CoachRecommendationAction[];
}
