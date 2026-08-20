import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import WorkoutTodayPage from "@/app/(app)/workout/today/page";

// O caminho que estava quebrado: primeiro usuário, exercício sem histórico
// (last_weight_kg e planned_weight_kg ausentes), peso do runtime vazio. Clicar em
// "Feito" caía num return antes de qualquer evento — a série não avançava e o
// abandono era indistinguível de alguém que nunca tentou.
//
// A entrada por quick workout é usada de propósito: é o caminho que monta o
// runtime SEM pré-preencher peso, exatamente o estado do bug.

const { trackEventMock, trackOnceMock, apiGet, apiPost, apiPatch } = vi.hoisted(() => ({
  trackEventMock: vi.fn(),
  trackOnceMock: vi.fn(),
  apiGet: vi.fn(),
  apiPost: vi.fn(),
  apiPatch: vi.fn(),
}));

vi.mock("@/shared/lib/analytics", () => ({
  trackEvent: trackEventMock,
  trackOnce: trackOnceMock,
  EVENTS: {
    SCREEN_VIEW: "screen_view",
    WORKOUT_STARTED: "workout_started",
    WORKOUT_COMPLETED: "workout_completed",
    WORKOUT_EXERCISE_COMPLETED: "workout_exercise_completed",
    EXERCISE_WEIGHT_CHANGED: "exercise_weight_changed",
    EXERCISE_SET_COMPLETION_ATTEMPTED: "exercise_set_completion_attempted",
    EXERCISE_SET_COMPLETED: "exercise_set_completed",
    EXERCISE_LOAD_PROGRESSED: "exercise_load_progressed",
    PAYWALL_VIEWED: "paywall_viewed",
  },
}));

vi.mock("@/shared/lib/api", () => ({
  api: { get: apiGet, post: apiPost, patch: apiPatch },
  ApiError: class ApiError extends Error { status = 500; },
}));

let searchParams = "quick=1";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(searchParams),
}));

vi.mock("@/shared/components/upgrade-gate", () => ({
  UpgradeGate: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock("@/features/coach/coach-context", () => ({
  useCoach: () => ({ setScreen: vi.fn(), registerExec: vi.fn(), open: vi.fn() }),
}));

// Parcial: só o hook precisa ser controlado; formatElapsed e o resto do módulo
// continuam sendo os reais.
vi.mock(import("@/features/workout/workout-session-context"), async (importOriginal) => ({
  ...(await importOriginal()),
  useWorkoutSession: () => ({
    startTime: Date.now(),
    elapsedSeconds: 0,
    beginSession: vi.fn(),
    endSession: vi.fn(),
    saveRestEnd: vi.fn(),
    getRestEnd: () => null,
  }),
}));

vi.mock("@/features/auth/auth-context", () => ({
  useAuth: () => ({ user: { id: 1, billing_status: { paid: true, status: "active" } }, updateUser: vi.fn() }),
}));

function strengthExercise(overrides: Record<string, unknown> = {}) {
  return {
    workout_day_exercise_id: 101,
    exercise_id: 501,
    name: "Supino reto",
    muscle_group: "chest",
    exercise_type: "strength",
    sets: 3,
    reps: 10,
    rest_seconds: 60,
    description: "",
    image_url: "",
    muscle_image_url: "",
    // Primeiro contato: nenhum histórico de carga. É isto que deixava
    // weight_by_set = [""] e disparava o bloqueio.
    last_weight_kg: null,
    planned_weight_kg: null,
    ...overrides,
  };
}

function quickDay(exercises: unknown[]) {
  return { id: null, name: "Treino rápido", quick: true, exercises };
}

function renderWithQuickDay(exercises: unknown[]) {
  sessionStorage.setItem("wk_quick_day", JSON.stringify(quickDay(exercises)));
  return render(<WorkoutTodayPage />);
}

/** Avança da tela de aquecimento para a execução. */
async function startExercising(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole("button", { name: /Estou pronto/i }));
}

/**
 * O "+" do peso. A tela tem vários +/- (séries, reps, descanso), então o
 * seletor precisa ser ancorado no rótulo do próprio bloco de peso.
 */
function weightPlusButton() {
  const weightBox = screen.getByText(/peso · \+/).closest("div")!;
  return within(weightBox).getByRole("button", { name: "+" });
}

/** Entre séries a página entra na fase de descanso. */
async function skipRest(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole("button", { name: /Pular descanso/i }));
}

function eventsNamed(name: string) {
  return trackEventMock.mock.calls.filter(([eventName]) => eventName === name);
}

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  searchParams = "quick=1";
  apiGet.mockResolvedValue({ day: null });
  apiPost.mockResolvedValue({ id: 1 });
  apiPatch.mockResolvedValue({});
  // jsdom não implementa Web Audio, e handleSetDone chama unlockAudio() logo na
  // primeira linha. Stub mínimo com o que a página realmente usa.
  vi.stubGlobal("AudioContext", class FakeAudioContext {
    currentTime = 0;
    destination = {};
    state = "running";
    createBuffer() { return {}; }
    createBufferSource() {
      return { buffer: null, connect: () => {}, start: () => {}, stop: () => {} };
    }
    createOscillator() {
      return {
        type: "sine",
        connect: () => {},
        start: () => {},
        stop: () => {},
        frequency: { value: 0, setValueAtTime: () => {} },
      };
    }
    createGain() {
      return {
        connect: () => {},
        gain: {
          value: 0,
          setValueAtTime: () => {},
          exponentialRampToValueAtTime: () => {},
          linearRampToValueAtTime: () => {},
        },
      };
    }
    resume() { return Promise.resolve(); }
    close() { return Promise.resolve(); }
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("A) série sem peso — não bloqueia", () => {
  it("avança a série ao clicar em Feito com o peso vazio", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    expect(await screen.findByRole("button", { name: /Feito — série 1\/3/i })).toBeInTheDocument();
    // O peso está mesmo vazio: é este estado que antes barrava o clique.
    expect(screen.getByText("— kg")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Feito — série 1\/3/i }));

    // Série avançou. Antes, o clique não produzia efeito nenhum.
    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));
  });

  it("emite a tentativa e a conclusão, reportando ausência de peso", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/3/i }));

    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));

    expect(eventsNamed("exercise_set_completion_attempted")[0][1]).toMatchObject({
      exercise_id: 501,
      workout_day_exercise_id: 101,
      set_number: 1,
      planned_sets: 3,
      has_weight: false,
      is_cardio: false,
      source: "workout_today",
    });
    expect(eventsNamed("exercise_set_completed")[0][1]).toMatchObject({
      set_number: 1,
      has_weight: false,
      current_weight: 0,
      source: "workout_today",
    });
  });

  it("não dispara progressão de carga quando não houve peso", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/3/i }));

    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));
    expect(eventsNamed("exercise_load_progressed")).toHaveLength(0);
  });
});

describe("B) série com peso — sem regressão", () => {
  it("preserva o peso informado e reporta presença", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    await screen.findByRole("button", { name: /Feito — série 1\/3/i });
    // Um toque no "+" a partir de vazio informa 1 kg (passo inicial).
    await user.click(weightPlusButton());
    expect(await screen.findByText("1 kg")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Feito — série 1\/3/i }));

    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));
    expect(eventsNamed("exercise_set_completed")[0][1]).toMatchObject({
      has_weight: true,
      current_weight: 1,
    });
    expect(eventsNamed("exercise_set_completion_attempted")[0][1]).toMatchObject({
      has_weight: true,
    });
  });
});

describe("C) cardio — sem regressão", () => {
  it("conclui pelo CTA próprio, sem eventos de série", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([
      strengthExercise({ exercise_type: "cardio", muscle_group: null, name: "Esteira", duration_minutes: 10 }),
    ]);
    await startExercising(user);

    const cardioCta = await screen.findByRole("button", { name: /Concluir cardio/i });
    expect(screen.queryByRole("button", { name: /Feito — série/i })).not.toBeInTheDocument();

    await user.click(cardioCta);

    // Cardio nunca passa por handleSetDone — não tem séries a instrumentar.
    expect(eventsNamed("exercise_set_completion_attempted")).toHaveLength(0);
    expect(eventsNamed("exercise_set_completed")).toHaveLength(0);
    // Mas produz o degrau comparável entre superfícies.
    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(1));
  });
});

describe("D) idempotência do clique", () => {
  it("duplo clique não produz duas conclusões da mesma série", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    const cta = await screen.findByRole("button", { name: /Feito — série 1\/3/i });
    await user.dblClick(cta);

    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));
    expect(eventsNamed("exercise_set_completed")).toHaveLength(1);
  });

  it("a série seguinte ainda pode ser concluída depois de um duplo clique", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    await user.dblClick(await screen.findByRole("button", { name: /Feito — série 1\/3/i }));
    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));

    // A guarda é por identidade (wde:set), não temporal: a série 2 tem outra
    // chave e precisa passar normalmente.
    await skipRest(user);
    await user.click(await screen.findByRole("button", { name: /Feito — série 2\/3/i }));

    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(2));
    expect(eventsNamed("exercise_set_completed")[1][1]).toMatchObject({ set_number: 2 });
  });

  it("a tentativa é emitida antes da conclusão", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise()]);
    await startExercising(user);

    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/3/i }));
    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));

    const names = trackEventMock.mock.calls.map(([name]) => name);
    expect(names.indexOf("exercise_set_completion_attempted"))
      .toBeLessThan(names.indexOf("exercise_set_completed"));
  });
});

// ── Blocos compostos ────────────────────────────────────────────────────────
// Num superset, finishExercise roda UMA vez só, no último membro. Emitir apenas
// pelo exercício atual faria workout_exercise_completed significar "1 exercício"
// na tela anônima e "1 bloco de até 3" aqui — o mesmo nome medindo coisas
// diferentes. Estes testes fixam a semântica: um evento por exercício concluído.

function supersetMember(position: number, overrides: Record<string, unknown> = {}) {
  return strengthExercise({
    workout_day_exercise_id: 200 + position,
    exercise_id: 600 + position,
    name: `Superset ${position + 1}`,
    sets: 1,
    block_id: 9,
    block_type: "superset",
    position_in_block: position,
    block_rounds: 1,
    rest_seconds: 60,
    ...overrides,
  });
}

/** Percorre a rodada única do superset: A1 → A2 → A3 → feedback. */
async function completeSuperset(user: ReturnType<typeof userEvent.setup>, size: number) {
  for (let i = 0; i < size; i++) {
    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));
  }
}

/** O chip de sentimento que encerra o exercício (tela exercise_feedback). */
async function feelingButton() {
  return await screen.findByRole("button", { name: "Bem" });
}

async function chooseFeeling(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await feelingButton());
}

function completedExerciseIds() {
  return eventsNamed("workout_exercise_completed").map(([, props]) => props.exercise_id);
}

describe("E) bloco composto — um evento por exercício individual", () => {
  it("superset de 3 concluídos emite exatamente 3 eventos, um por exercício", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([supersetMember(0), supersetMember(1), supersetMember(2)]);
    await startExercising(user);

    await completeSuperset(user, 3);
    await chooseFeeling(user);

    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(3));
    // A1 e A2 foram integralmente executados e antes produziam zero eventos.
    expect(completedExerciseIds().sort()).toEqual([600, 601, 602]);
  });

  it("exercício simples emite exatamente 1 evento, com o exercise_id correto", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([strengthExercise({ sets: 1 })]);
    await startExercising(user);

    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));
    await chooseFeeling(user);

    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(1));
    expect(completedExerciseIds()).toEqual([501]);
  });

  it("não emite para exercício que o usuário nunca alcançou", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([
      supersetMember(0),
      supersetMember(1),
      // Fora do bloco e depois dele: o treino é encerrado antes de chegar aqui.
      strengthExercise({ workout_day_exercise_id: 999, exercise_id: 777, name: "Nunca alcançado", sets: 1 }),
    ]);
    await startExercising(user);

    await completeSuperset(user, 2);
    await chooseFeeling(user);

    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(2));
    expect(completedExerciseIds()).not.toContain(777);
  });

  it("duplo toque no feedback não duplica os eventos do bloco", async () => {
    const user = userEvent.setup();
    renderWithQuickDay([supersetMember(0), supersetMember(1), supersetMember(2)]);
    await startExercising(user);

    await completeSuperset(user, 3);
    await user.dblClick(await feelingButton());

    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(3));
    expect(eventsNamed("workout_exercise_completed")).toHaveLength(3);
  });
});

// ── Reset dos guards numa nova execução ─────────────────────────────────────
// Os guards de deduplicação são refs do componente, e startWorkout() só troca a
// fase — não desmonta nada. Reiniciar o mesmo treino é comportamento observado
// em produção (mesma sessão, mesmo workout_day_id), e sem reset a segunda
// execução ficaria parcialmente muda: o mesmo par (exercício, série) e os
// exercícios já reportados seriam lidos como repetição de clique.

const PLAN_DAY = {
  id: 42,
  name: "Treino A",
  exercises: [strengthExercise({ sets: 1, rest_seconds: 0 })],
};

function renderWithPlanDay() {
  searchParams = "day=42";
  apiGet.mockImplementation((path: string) => {
    if (path === "/api/v1/workout_plan") return Promise.resolve({ id: 7, days: [{ id: 42 }] });
    if (path.startsWith("/api/v1/workout_sessions")) return Promise.resolve({ sessions: [], total: 0 });
    if (path === "/api/v1/workout_days/42") return Promise.resolve({ day: PLAN_DAY });
    return Promise.resolve({ day: null });
  });
  return render(<WorkoutTodayPage />);
}

/**
 * Do fim do exercício de volta à visão geral: recuperação → extras opcionais →
 * pré-conclusão → "adicionar exercício". É o caminho in-page que permite
 * reiniciar o mesmo treino sem recarregar — o que o user 555 fez em produção.
 */
async function backToOverview(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole("button", { name: /Finalizar treino →/i }));
  await user.click(await screen.findByRole("button", { name: /Finalizar treino agora/i }));
  const addExercise = await screen.findAllByRole("button", { name: /Adicionar core/i });
  await user.click(addExercise[0]);
}

/** Da tela de visão geral até a execução, passando pelo startWorkout() real. */
async function startRun(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole("button", { name: "Iniciar treino" }));
  await startExercising(user);
}

describe("F) nova execução do mesmo treino reseta os guards", () => {
  it("o mesmo exercício/série volta a emitir depois de um novo startWorkout()", async () => {
    const user = userEvent.setup();
    renderWithPlanDay();

    // 1ª execução
    await startRun(user);
    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));
    await chooseFeeling(user);
    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(1));
    expect(eventsNamed("workout_exercise_completed")).toHaveLength(1);

    await backToOverview(user);

    // 2ª execução, mesmo treino, mesmo exercício, mesma série
    await startRun(user);
    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));

    // Sem o reset, o guard da execução anterior engoliria este evento.
    await waitFor(() => expect(eventsNamed("exercise_set_completed")).toHaveLength(2));
    expect(eventsNamed("exercise_set_completed")[1][1]).toMatchObject({ set_number: 1 });
  });

  it("workout_exercise_completed volta a emitir para o mesmo exercício", async () => {
    const user = userEvent.setup();
    renderWithPlanDay();

    await startRun(user);
    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));
    await chooseFeeling(user);
    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(1));

    await backToOverview(user);

    await startRun(user);
    await user.click(await screen.findByRole("button", { name: /Feito — série 1\/1/i }));
    await chooseFeeling(user);

    await waitFor(() => expect(eventsNamed("workout_exercise_completed")).toHaveLength(2));
    expect(completedExerciseIds()).toEqual([501, 501]);
  });
});
