import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach } from "vitest";
import AnonymousWorkoutPage from "@/app/(anon)/plano/treino/page";

// Esta tela é a SEGUNDA superfície de execução de treino. Ela não tem séries —
// é um checkbox por exercício. Por isso nunca poderá emitir
// exercise_set_completed, e usar esse evento como degrau do funil contava a tela
// inteira como zero por construção, não por comportamento.
// workout_exercise_completed é o degrau comparável com /workout/today.

const { trackEventMock, fetchDay, fetchToday, recordSession } = vi.hoisted(() => ({
  trackEventMock: vi.fn(),
  fetchDay: vi.fn(),
  fetchToday: vi.fn(),
  recordSession: vi.fn(),
}));

vi.mock("@/shared/lib/analytics", () => ({ trackEvent: trackEventMock }));

vi.mock("@/features/anonymous/anonymous-plan", () => ({
  fetchAnonymousDay: fetchDay,
  fetchAnonymousToday: fetchToday,
  recordAnonymousSession: recordSession,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  useSearchParams: () => new URLSearchParams(""),
}));

vi.mock("@/shared/components/workout/exercise-info-modal", () => ({
  ExerciseInfoModal: () => null,
}));

const DAY = {
  id: 11,
  name: "Treino A",
  exercises: [
    { workout_day_exercise_id: 101, exercise_id: 501, name: "Supino", sets: 3, reps: 10, rest_seconds: 60 },
    { workout_day_exercise_id: 102, exercise_id: 502, name: "Remada", sets: 3, reps: 10, rest_seconds: 60 },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
  fetchToday.mockResolvedValue({ day: DAY });
  recordSession.mockResolvedValue({});
});

function eventsNamed(name: string) {
  return trackEventMock.mock.calls.filter(([eventName]) => eventName === name);
}

describe("execução anônima — workout_exercise_completed", () => {
  it("emite ao marcar um exercício como feito", async () => {
    const user = userEvent.setup();
    render(<AnonymousWorkoutPage />);

    await user.click(await screen.findByRole("button", { name: /Marcar Supino como feito/i }));

    expect(eventsNamed("workout_exercise_completed")).toHaveLength(1);
    expect(eventsNamed("workout_exercise_completed")[0][1]).toMatchObject({
      source: "anonymous",
      workout_day_id: 11,
      workout_day_exercise_id: 101,
      exercise_id: 501,
    });
  });

  it("NÃO emite ao desmarcar — desmarcar é correção, não conclusão", async () => {
    const user = userEvent.setup();
    render(<AnonymousWorkoutPage />);

    const checkbox = await screen.findByRole("button", { name: /Marcar Supino como feito/i });
    await user.click(checkbox);
    await user.click(await screen.findByRole("button", { name: /Desmarcar Supino/i }));

    expect(eventsNamed("workout_exercise_completed")).toHaveLength(1);
  });

  it("emite uma vez por exercício distinto", async () => {
    const user = userEvent.setup();
    render(<AnonymousWorkoutPage />);

    await user.click(await screen.findByRole("button", { name: /Marcar Supino como feito/i }));
    await user.click(await screen.findByRole("button", { name: /Marcar Remada como feito/i }));

    expect(eventsNamed("workout_exercise_completed")).toHaveLength(2);
  });
});

describe("execução anônima — eventos de série não existem aqui", () => {
  it("nunca emite exercise_set_completed nem a tentativa", async () => {
    const user = userEvent.setup();
    render(<AnonymousWorkoutPage />);

    await user.click(await screen.findByRole("button", { name: /Marcar Supino como feito/i }));
    await user.click(await screen.findByRole("button", { name: /Marcar Remada como feito/i }));
    await user.click(screen.getByRole("button", { name: /Concluir treino/i }));

    await waitFor(() => expect(recordSession).toHaveBeenCalled());

    // Sintetizar uma série a partir de um checkbox seria fabricar dado. A
    // ausência é a resposta correta — e o funil precisa saber disso.
    expect(eventsNamed("exercise_set_completed")).toHaveLength(0);
    expect(eventsNamed("exercise_set_completion_attempted")).toHaveLength(0);
  });

  it("mantém o degrau de primeiro exercício iniciado", async () => {
    const user = userEvent.setup();
    render(<AnonymousWorkoutPage />);

    await user.click(await screen.findByRole("button", { name: /Marcar Supino como feito/i }));

    expect(eventsNamed("workout_first_exercise_started")).toHaveLength(1);
  });
});
