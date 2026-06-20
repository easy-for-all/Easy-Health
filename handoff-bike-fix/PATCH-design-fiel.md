# Porte FIEL do design (4 engines) para o app real

Objetivo: a execução de Bike/Corrida/HIIT/Funcional/Mobilidade/Alongamento ficar
com o **visual do protótipo** (timer gigante, bloco atual/próximo, métricas, anel
de intervalado, recuperação com mídia + respiração) — não só "sem séries/kg".

São 2 entregas:
- **A) Correção de roteamento** (engine) — obrigatória. Ver `PATCH.md`.
- **B) Porte visual** (este arquivo) — as telas ricas.

> Faça A primeiro (cria `workout-engine.ts` e conserta `isCardio/isTimed`).
> Depois B troca o VISUAL dos painéis não-musculação.

---

## Arquivos
1. `workout-engine.ts`            → `src/features/workout/` (já no passo A)
2. `workout-engine-screens.tsx`   → `app/workout/today/`

## Edição em `app/workout/today/page.tsx`

### 1. Imports (topo)
```tsx
import { workoutEngine } from "@/features/workout/workout-engine";
import { CardioPanel, IntervalPanel, RecoveryPanel } from "./workout-engine-screens";
```

### 2. Helpers de classificação
Garanta os helpers do passo A e ADICIONE `isInterval`:
```tsx
function isCardio(ex: WorkoutDayExercise) {
  const e = workoutEngine(ex);
  return e === "cardio" || e === "interval"; // ambos rodam o cronômetro
}
function isInterval(ex: WorkoutDayExercise) {
  return workoutEngine(ex) === "interval";   // só p/ escolher o VISUAL
}
function isTimed(ex: WorkoutDayExercise) {
  return workoutEngine(ex) === "recovery";
}
```
(`isCardio` continua true p/ interval → o efeito que liga `cardioTimeLeft` segue funcionando.)

### 3. Corpo do exercício (fase "exercising")
Hoje o corpo é:
```tsx
{isTimed(exercise) ? ( /* painel timed */ )
 : isCardio(exercise) ? ( /* painel cardio simples */ )
 : ( /* painel de FORÇA */ )}
```

SUBSTITUA os ramos `isTimed` e `isCardio` (NÃO mexa no ramo de FORÇA) por:

```tsx
{isTimed(exercise) ? (
  <RecoveryPanel
    exerciseName={exercise.name}
    nextName={exercises[currentIndex + 1]?.name ?? null}
    imageUrl={exercise.image_url}
    gifUrl={exercise.gif_url ?? undefined}
    instruction={exercise.instructions ?? exercise.description ?? undefined}
    side={null}
    elapsedSeconds={timedElapsed}
    targetSeconds={(exercise.duration_minutes ?? 1) * 60}
    running={timedRunning}
    onToggle={() => setTimedRunning((r) => !r)}
    onOpenMedia={() => setGifModalExercise(exercise)}
  />
) : isInterval(exercise) ? (
  <IntervalPanel
    exerciseName={exercise.name}
    nextName={exercises[currentIndex + 1]?.name ?? null}
    secondsLeft={cardioTimeLeft}
    totalSeconds={(exercise.duration_minutes ?? 20) * 60}
    blockIndex={currentIndex + 1}
    blockTotal={exercises.length}
  />
) : isCardio(exercise) ? (
  <CardioPanel
    exerciseName={exercise.name}
    nextName={exercises[currentIndex + 1]?.name ?? null}
    secondsLeft={cardioTimeLeft}
    totalSeconds={(exercise.duration_minutes ?? 20) * 60}
    intensity={runtime.intensity ?? "Moderada"}
    durationMin={runtime.duration_minutes ?? exercise.duration_minutes}
    blockIndex={currentIndex + 1}
    blockTotal={exercises.length}
  />
) : (
  /* ── mantém EXATAMENTE o painel de FORÇA atual ── */
)}
```

### 4. CTA do rodapé (já existe — só confira)
O rodapé atual já trata os 3 casos e continua válido:
- `isTimed` → "Concluir — mm:ss" (recuperação)
- `isCardio` → "Concluir cardio" (cardio e intervalado)
- senão → "Feito — série X/N" (força)

Nada a mudar ali. (Opcional: trocar o texto "Concluir cardio" por
"Concluir bloco" quando `isInterval(exercise)`.)

---

## Por que fica fiel
- **Cardio**: tempo restante gigante + "Bloco atual/Próximo" + métricas (intensidade,
  duração). Igual ao protótipo, sem séries/reps/peso.
- **Intervalado**: anel de tempo com fase "TRABALHO", "Bloco X de N", pontos de
  progresso, próximo. O descanso entre blocos continua usando a sua tela de
  descanso (anel) que já existe.
- **Recuperação**: mídia grande (GIF/imagem da base oficial), nome, anel de
  tempo-alvo, animação de respiração, instrução e próximo.
- **Musculação**: 100% intacta.

## Ajuste de tokens (se necessário)
Os componentes usam variáveis do seu tema (`--bg`, `--primary`, `--primary-soft`,
`--surface`, `--text`, `--text-muted`, `--hot`, `--border`). Já vi todas em uso no
seu `page.tsx`. Onde não existir, há fallback embutido (ex.: `var(--text-dim,#6b7280)`).
Se quiser, me mande o `globals.css` / tema que eu confirmo 1:1.

## Validação
1. Treino Rápido → **Bike**: cronômetro grande + bloco/próximo + intensidade. Sem séries/kg.
2. **HIIT/Funcional**: anel "TRABALHO" + Bloco X de N + pontos.
3. **Mobilidade/Alongamento**: mídia grande + respiração + tempo-alvo.
4. **Musculação**: séries/reps/peso/descanso como antes.

## Evolução futura (fora deste porte)
Intervalado "de verdade" (blocos work/rest internos a UM exercício, com troca
automática de fase) exige o backend devolver a estrutura de ciclos. Hoje cada
bloco = um exercício da lista, o que já dá a experiência correta. Quando o
gerador suportar ciclos, o `IntervalPanel` recebe os blocos reais sem reescrita.
