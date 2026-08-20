import { describe, it, expect } from "vitest";
import {
  buildSetCompletion,
  setCompletionKey,
  hasExerciseProgress,
  completedSetCount,
} from "@/features/workout/set-completion";

// A regra que este arquivo protege: peso NÃO é obrigatório para concluir uma
// série. Antes, /workout/today retornava cedo quando o peso estava vazio, e o
// primeiro usuário de um exercício sem histórico (planned_weight e
// last_weight ausentes) não conseguia avançar da primeira série.

const base = {
  planned_sets: 3,
  reps_by_set: [10, 10, 10],
  weight_by_set: ["", "", ""],
  warmup_by_set: [false, false, false],
};

describe("buildSetCompletion — série SEM peso", () => {
  it("conclui a série e reporta ausência de peso", () => {
    const result = buildSetCompletion(base, 1, 10);

    expect(result.hasWeight).toBe(false);
    expect(result.currentWeightNumber).toBe(0);
  });

  it("não inventa peso para a próxima série", () => {
    const result = buildSetCompletion(base, 1, 10);

    // Ausência propagada como ausência: string vazia, que o payload converte em
    // null. Nunca "0" — o domínio inteiro lê 0 como "não informado", e gravá-lo
    // faria um peso fabricado entrar no histórico de progressão de carga.
    expect(result.weightBySet[1]).toBe("");
    expect(result.weightBySet).toEqual(["", "", ""]);
  });

  it("registra as reps da série concluída", () => {
    const result = buildSetCompletion(base, 1, 10);

    // completionData conta uma série como feita por reps > 0 OU peso > 0. Sem
    // isto, uma série sem peso seria concluída na tela e contada como pulada.
    expect(result.repsBySet[0]).toBe(10);
  });
});

describe("buildSetCompletion — série COM peso", () => {
  const withWeight = { ...base, weight_by_set: ["40", "", ""] };

  it("preserva o peso informado e reporta presença", () => {
    const result = buildSetCompletion(withWeight, 1, 10);

    expect(result.hasWeight).toBe(true);
    expect(result.currentWeightNumber).toBe(40);
    expect(result.weightBySet[0]).toBe("40");
  });

  it("propaga o peso para a próxima série", () => {
    const result = buildSetCompletion(withWeight, 1, 10);

    expect(result.weightBySet[1]).toBe("40");
  });

  it("não sobrescreve um peso que a próxima série já tinha", () => {
    const result = buildSetCompletion({ ...base, weight_by_set: ["40", "50", ""] }, 1, 10);

    expect(result.weightBySet[1]).toBe("50");
  });

  it("não propaga peso a partir da última série", () => {
    const result = buildSetCompletion({ ...base, weight_by_set: ["", "", "60"] }, 3, 10);

    expect(result.weightBySet).toEqual(["", "", "60"]);
  });

  it("peso 0 explícito conta como informado", () => {
    // "0" é um valor que o usuário digitou (peso corporal, por exemplo). É
    // diferente de "", e has_weight é justamente o que torna os dois
    // distinguíveis no evento, já que current_weight é 0 nos dois casos.
    const result = buildSetCompletion({ ...base, weight_by_set: ["0", "", ""] }, 1, 10);

    expect(result.hasWeight).toBe(true);
    expect(result.currentWeightNumber).toBe(0);
  });
});

describe("buildSetCompletion — warmup", () => {
  it("não contamina a próxima série com a carga do aquecimento", () => {
    const result = buildSetCompletion(
      {
        planned_sets: 3,
        reps_by_set: [10, 10, 10],
        weight_by_set: ["60", "20", ""],
        warmup_by_set: [false, true, false],
      },
      2,
      10,
    );

    // Série 2 é warmup: a série 3 recebe a última carga NÃO-warmup (60), não os
    // 20 do aquecimento.
    expect(result.weightBySet[2]).toBe("60");
  });

  it("deixa a próxima série vazia quando não houve carga real antes do warmup", () => {
    const result = buildSetCompletion(
      {
        planned_sets: 2,
        reps_by_set: [10, 10],
        weight_by_set: ["20", ""],
        warmup_by_set: [true, false],
      },
      1,
      10,
    );

    expect(result.weightBySet[1]).toBe("");
  });
});

describe("buildSetCompletion — reps ausentes", () => {
  it("mantém reps 0 quando o exercício chega sem reps", () => {
    // Risco declarado: WorkoutDayExercise valida reps > 0 para exercícios de
    // plano, mas um exercício sintético (quick workout) poderia chegar sem. Aí a
    // série ficaria sem reps E sem peso, e completionData a contaria como pulada.
    // Documentado aqui para que a mudança fique visível se alguém a introduzir.
    const result = buildSetCompletion({ ...base, reps_by_set: [0, 0, 0] }, 1, 0);

    expect(result.repsBySet[0]).toBe(0);
  });
});

describe("setCompletionKey", () => {
  it("distingue séries diferentes do mesmo exercício", () => {
    expect(setCompletionKey(7, 1)).not.toBe(setCompletionKey(7, 2));
  });

  it("distingue a mesma série de exercícios diferentes", () => {
    expect(setCompletionKey(7, 1)).not.toBe(setCompletionKey(8, 1));
  });

  it("é estável para a mesma série — é isto que barra o duplo toque", () => {
    expect(setCompletionKey(7, 1)).toBe(setCompletionKey(7, 1));
  });
});

describe("hasExerciseProgress — regra canônica de 'exercício executado'", () => {
  const empty = { planned_sets: 3, reps_by_set: [0, 0, 0], weight_by_set: ["", "", ""] };

  it("strength: série com reps conta como executado", () => {
    expect(hasExerciseProgress("strength", { ...empty, reps_by_set: [10, 0, 0] })).toBe(true);
  });

  it("strength: série só com peso também conta", () => {
    expect(hasExerciseProgress("strength", { ...empty, weight_by_set: ["40", "", ""] })).toBe(true);
  });

  it("strength: nada registrado → não executado", () => {
    expect(hasExerciseProgress("strength", empty)).toBe(false);
  });

  it("cardio: usa duration_minutes", () => {
    expect(hasExerciseProgress("cardio", { ...empty, duration_minutes: 20 })).toBe(true);
    expect(hasExerciseProgress("cardio", { ...empty, duration_minutes: 0 })).toBe(false);
    expect(hasExerciseProgress("cardio", empty)).toBe(false);
  });

  it("timed: usa elapsed_seconds", () => {
    expect(hasExerciseProgress("timed", { ...empty, elapsed_seconds: 45 })).toBe(true);
    expect(hasExerciseProgress("timed", { ...empty, elapsed_seconds: 0 })).toBe(false);
  });

  it("timed tem precedência sobre duração planejada", () => {
    // Um exercício timed com duration_minutes do plano mas sem tempo decorrido
    // NÃO foi executado — é o que distingue timed de cardio.
    expect(hasExerciseProgress("timed", { ...empty, duration_minutes: 10, elapsed_seconds: 0 })).toBe(false);
  });
});

describe("completedSetCount", () => {
  it("conta séries com reps OU peso", () => {
    expect(completedSetCount({
      planned_sets: 3,
      reps_by_set: [10, 0, 0],
      weight_by_set: ["", "40", ""],
    })).toBe(2);
  });

  it("zero quando nada foi registrado", () => {
    expect(completedSetCount({ planned_sets: 2, reps_by_set: [0, 0], weight_by_set: ["", ""] })).toBe(0);
  });
});
