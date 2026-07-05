const GYM_EQUIPMENT_TYPES = ["gym", "dumbbell", "barbell", "cable", "machine"] as const;
const GIFDOTREINO_PREFIX = "/exercise-images/gifdotreino/";

type ExerciseForImage = {
  exercise_type?: string | null;
  equipment_type?: string | null;
  image_url?: string | null;
  gif_url?: string | null;
};

export function isGymExercise(exercise: Pick<ExerciseForImage, "exercise_type" | "equipment_type">): boolean {
  return (
    exercise.exercise_type === "musculacao" ||
    GYM_EQUIPMENT_TYPES.includes((exercise.equipment_type ?? "") as (typeof GYM_EQUIPMENT_TYPES)[number])
  );
}

// Returns the image URL only if it is from the official gifdotreino source.
export function getGymSafeImageUrl(exercise: ExerciseForImage): string | null {
  const url = exercise.gif_url || exercise.image_url;
  if (!url) return null;
  return url.startsWith(GIFDOTREINO_PREFIX) && url.toLowerCase().endsWith(".gif") ? url : null;
}
