import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SwapModal } from "@/app/(app)/workout/today/swap-modal";
import type { WorkoutDayExercise } from "@/shared/types/workout";

const { apiGet, apiPost, apiDelete, apiUploadPost } = vi.hoisted(() => ({
  apiGet: vi.fn(),
  apiPost: vi.fn(),
  apiDelete: vi.fn(),
  apiUploadPost: vi.fn(),
}));

vi.mock("@/shared/lib/api", () => ({
  api: {
    get: apiGet,
    post: apiPost,
    delete: apiDelete,
    uploadPost: apiUploadPost,
  },
}));

vi.mock("@/shared/utils/exercise-image", () => ({
  getGymSafeImageUrl: () => null,
}));

vi.mock("@/shared/components/ai-trainer", () => ({
  AITrainerAvatar: () => <div data-testid="ai-trainer-avatar" />,
  AITrainerBubble: ({ message }: { message: string }) => <div>{message}</div>,
}));

const exercise: WorkoutDayExercise = {
  workout_day_exercise_id: 14385,
  exercise_id: 100,
  name: "Tríceps corda",
  muscle_group: "triceps",
  exercise_type: "musculacao",
  description: "Atual",
  image_url: "",
  muscle_image_url: "",
  sets: 3,
  reps: 10,
  rest_seconds: 60,
  order_index: 0,
};

const alternative = {
  id: 1621,
  name: "Tríceps banco",
  muscle_group: "triceps",
  exercise_type: "musculacao",
  description: "Alternativa",
  image_url: "",
  muscle_image_url: "",
  is_favorite: false,
};

function timeoutError() {
  return Object.assign(new Error("signal timed out"), { name: "TimeoutError" });
}

async function renderSwapModal(onSwap = vi.fn().mockResolvedValue(undefined)) {
  render(
    <SwapModal
      exercise={exercise}
      allWorkoutExerciseIds={[exercise.exercise_id]}
      onSwap={onSwap}
      onClose={vi.fn()}
    />,
  );

  const label = await screen.findByText(alternative.name);
  const button = label.closest("button");
  if (!button) throw new Error("Alternative button not found");
  return { button, onSwap };
}

describe("SwapModal timeout handling", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    apiGet.mockResolvedValue([alternative]);
    apiPost.mockResolvedValue({ logged: true });
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("keeps suggestion feedback as non-blocking telemetry before swapping", async () => {
    const user = userEvent.setup();
    apiPost.mockRejectedValueOnce(timeoutError());
    const onSwap = vi.fn().mockResolvedValue(undefined);
    const { button } = await renderSwapModal(onSwap);

    await user.click(button);

    await waitFor(() => expect(onSwap).toHaveBeenCalledWith(14385, 1621));
    expect(apiPost).toHaveBeenCalledWith(
      "/api/v1/exercises/1621/suggestion_feedback",
      expect.objectContaining({
        event_type: "suggestion_accepted",
        current_exercise_id: 100,
      }),
    );
    expect(screen.queryByText(/Não foi possível trocar o exercício/i)).not.toBeInTheDocument();
  });

  it("contains a swap timeout and shows an inline retryable error", async () => {
    const user = userEvent.setup();
    const onSwap = vi.fn().mockRejectedValue(timeoutError());
    const { button } = await renderSwapModal(onSwap);

    await user.click(button);

    expect(await screen.findByText(/Não foi possível trocar o exercício/i)).toBeInTheDocument();
    expect(onSwap).toHaveBeenCalledTimes(1);
  });

  it("prevents duplicate swaps while one swap is pending", async () => {
    let resolveSwap: () => void = () => {};
    const onSwap = vi.fn(() => new Promise<void>((resolve) => { resolveSwap = resolve; }));
    const { button } = await renderSwapModal(onSwap);

    fireEvent.click(button);
    fireEvent.click(button);

    expect(onSwap).toHaveBeenCalledTimes(1);

    resolveSwap();
    await waitFor(() => expect(button).not.toBeDisabled());
  });
});
