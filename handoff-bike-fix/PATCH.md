# Correção — Bike (e demais modalidades) caindo na tela de musculação

## Diagnóstico
Em `app/workout/today/page.tsx` a tela decide o painel assim:

```tsx
isTimed(exercise) ? (painel isométrico)
  : isCardio(exercise) ? (painel cardio / cronômetro)
  : (painel de FORÇA — séries · reps · peso · descanso)
```

E a classificação é:
```tsx
const CARDIO_TYPES_SET = new Set(["cardio", "corrida", "caminhada", "hiit", "natacao"]);
function isCardio(ex) { return !ex.muscle_group && CARDIO_TYPES_SET.has(ex.exercise_type); }
const TIMED_TYPES_SET = new Set(["timed"]);
function isTimed(ex) { return TIMED_TYPES_SET.has(ex.exercise_type); }
```

**`bike` não está no set** (nem `funcional`, `mobilidade`, `alongamento`). Logo,
Bike cai no `else` = **painel de força** → mostra séries/reps/peso/descanso.
É o que aparece na tela "Aquecimento — Bike".

## Correção (mínima, alta fidelidade)
Centralizar a decisão numa fonte única (`workout-engine.ts`) e reescrever
APENAS os dois helpers. Toda a renderização existente (painel cardio,
painel timed, painel força, CTA do rodapé, resumo, save) continua igual —
só passa a classificar certo.

### Passo 1 — adicionar o arquivo
Copie `workout-engine.ts` para `src/features/workout/workout-engine.ts`.

### Passo 2 — editar `app/workout/today/page.tsx`

**2a. Adicione o import** junto aos outros imports do topo:
```tsx
import { workoutEngine } from "@/features/workout/workout-engine";
```

**2b. SUBSTITUA este bloco:**
```tsx
const CARDIO_TYPES_SET = new Set(["cardio", "corrida", "caminhada", "hiit", "natacao"]);
function isCardio(ex: WorkoutDayExercise) {
  return !ex.muscle_group && CARDIO_TYPES_SET.has(ex.exercise_type);
}

const TIMED_TYPES_SET = new Set(["timed"]);
function isTimed(ex: WorkoutDayExercise) {
  return TIMED_TYPES_SET.has(ex.exercise_type);
}
```

**POR este:**
```tsx
// Engine único de classificação (Força / Cardio / Intervalado / Recuperação).
// Cardio + Intervalado usam a tela de tempo (sem séries/reps/peso).
function isCardio(ex: WorkoutDayExercise) {
  const e = workoutEngine(ex);
  return e === "cardio" || e === "interval";
}
// Recuperação / isometria usam a tela de tempo-alvo (anel + respiração).
function isTimed(ex: WorkoutDayExercise) {
  return workoutEngine(ex) === "recovery";
}
```

Pronto. Com isso:
- **Bike** → `cardio` → painel de cronômetro (tempo/intensidade). Sem séries/reps/kg. ✅
- **Funcional / HIIT** → `interval` → painel de tempo (sem séries/kg). ✅
- **Mobilidade / Alongamento** → `recovery` → painel de tempo-alvo (anel). ✅
- **Musculação** → `strength` → painel de força intacto. ✅

### Passo 3 (opcional, recomendado) — aquecimento/cooldown por tipo
Em `app/workout/today/warmup-data.ts` a função `detectWorkoutType` só reconhece
`musculacao | corrida | cardio`. Para Bike/funcional usarem aquecimento de cardio,
troque-a por:

```tsx
import { workoutEngine } from "@/features/workout/workout-engine";

function detectWorkoutType(day: WorkoutDay): string {
  const exercises = day.exercises ?? [];
  if (!exercises.length) return "default";
  // usa o engine do treino para escolher aquecimento/desaquecimento
  const engines = exercises.map((e) => workoutEngine(e));
  if (engines.some((e) => e === "strength")) return "musculacao";
  if (exercises.some((e) => e.exercise_type === "corrida")) return "corrida";
  if (engines.some((e) => e === "cardio" || e === "interval")) return "cardio";
  return "default";
}
```
(Se mover `detectWorkoutType` exige o import no `page.tsx`, ele já estará lá pelo passo 2a.)

### Passo 4 (opcional) — rótulos PT-BR
Em `page.tsx`, o `TYPE_LABELS` não tem `bike`/`mobilidade`/`alongamento`.
Complete para os chips ficarem certos:
```tsx
const TYPE_LABELS: Record<string, string> = {
  musculacao: "Musculação", cardio: "Cardio", natacao: "Natação",
  corrida: "Corrida", funcional: "Funcional", caminhada: "Caminhada", hiit: "HIIT",
  bike: "Bike", mobilidade: "Mobilidade", alongamento: "Alongamento",
};
```

## Como validar
1. Gere um **Treino Rápido → Bike**. A execução deve mostrar **cronômetro**, não séries/peso.
2. Gere **Funcional** e **Mobilidade** — idem (tempo, não carga).
3. Gere **Musculação** — deve continuar com séries/reps/peso/descanso.

## Observação (próximo passo, fora desta correção)
O painel `cardio` atual é um cronômetro único. Para Intervalado de verdade
(blocos trabalho/descanso, "Bloco 4 de 10", próximo bloco), é uma evolução
maior na UI — dá pra fazer depois, reusando o mesmo engine. Esta correção já
elimina o bug de séries/reps/peso em todas as modalidades não-musculação.
