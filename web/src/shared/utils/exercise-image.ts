const GYM_EQUIPMENT_TYPES = ["gym", "dumbbell", "barbell", "cable", "machine"] as const;
const OFFICIAL_IMAGE_PREFIXES = ["/exercise-images/db/", "/exercise-images/gifdotreino/"] as const;

type ExerciseForImage = {
  exercise_type?: string | null;
  equipment_type?: string | null;
  image_url?: string | null;
};

export function isGymExercise(exercise: Pick<ExerciseForImage, "exercise_type" | "equipment_type">): boolean {
  return (
    exercise.exercise_type === "musculacao" ||
    GYM_EQUIPMENT_TYPES.includes((exercise.equipment_type ?? "") as (typeof GYM_EQUIPMENT_TYPES)[number])
  );
}

// Returns the image URL only if it is from the official Git-versioned source.
// For gym/musculacao exercises, external URLs are blocked and null is returned instead.
export function getGymSafeImageUrl(exercise: ExerciseForImage): string | null {
  const url = exercise.image_url;
  if (!url) return null;
  if (!isGymExercise(exercise)) return url;
  return OFFICIAL_IMAGE_PREFIXES.some((prefix) => url.startsWith(prefix)) ? url : null;
}
