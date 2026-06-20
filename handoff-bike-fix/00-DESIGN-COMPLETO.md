# EasyHealth — Porte do DESIGN COMPLETO (protótipo → app real)

## Boa notícia: a fundação já existe
Seu `globals.css` **já contém o sistema Lumen inteiro** (mesmos tokens, tipos
Bricolage/Hanken/Geist, `--primary oklch(0.685 0.17 258)`, `.h-lg`, `.eyebrow`,
animações). Logo, isto **não é um redesign** — é portar os **layouts/telas** do
protótipo reusando os tokens que você já tem. Todos os componentes deste pacote
usam essas variáveis → ficam fiéis sem ajuste de cor.

> Referência visual viva: abra o protótipo `EasyHealth Pro.html` (o que
> construímos aqui). Cada tela abaixo existe lá pra comparar 1:1.

---

## Mapa de telas: protótipo → app real

| # | Tela do protótipo | Rota / arquivo no seu app | O que muda | Entrega |
|---|---|---|---|---|
| 1 | **Picker de modalidade** (agrupado: Força/Cardio/Performance/Recuperação/Inteligente) | `app/workout/quick/page.tsx` — passo 1 (hoje lista plana) | trocar a lista plana pelo grid agrupado com tag de engine | ✅ `modality-picker.tsx` |
| 2 | **Ambiente + Equipamentos + Ramificações** (ambiente muda foco; "tem esteira/bike?"; sugerir troca) | `app/workout/quick/page.tsx` — passo 3 (hoje só local) | substituir o passo de local por ambiente+equip+condicional | ✅ `environment-step.tsx` |
| 3 | **Execução — Cardio contínuo** | `app/workout/today/page.tsx` (fase exercising) | painel cardio rico | ✅ `workout-engine-screens.tsx` (`CardioPanel`) |
| 4 | **Execução — Intervalado** | idem | anel "TRABALHO" + Bloco X/N | ✅ `IntervalPanel` |
| 5 | **Execução — Recuperação** | idem | mídia grande + respiração + tempo-alvo | ✅ `RecoveryPanel` |
| 6 | **Roteamento de engine** (Bike etc. não cair em força) | `app/workout/today/page.tsx` + `workout-engine.ts` | classificador único | ✅ `workout-engine.ts` + `PATCH.md` |
| 7 | **Gerenciar treino** agrupado/editável (ciclos: "6 ciclos · 2min/1min") | `app/workout/today/page.tsx` — modal "Gerenciar treino" | p/ cardio/interval mostrar ciclos agrupados editáveis em vez de lista de exercícios | 📐 SPEC (abaixo) |
| 8 | **Treinos** (lista) | `app/workout/today` `ChooseScreen` / `/workouts` | já bem próximo; alinhar hero "Treino de hoje" + histórico | 📐 SPEC |
| 9 | Dashboard, Overview, Done, Onboarding | respectivos | já usam Lumen; ajustes finos | 📐 SPEC |

✅ = componente pronto neste pacote · 📐 = especificação p/ implementar com o seu Claude Code usando o protótipo como referência.

---

## Ordem recomendada de implementação
1. **Engines (6,3,4,5)** — corrige o bug + dá o design das telas de treino. (`PATCH.md` → `PATCH-design-fiel.md`)
2. **Picker agrupado (1)** — `modality-picker.tsx` no passo 1 do quick.
3. **Ambiente+Equip (2)** — `environment-step.tsx` no passo 3 do quick.
4. **Gerenciar treino (7)** e **Treinos (8)** — pelos SPECs.

---

## Como plugar os componentes 1 e 2 (passo a passo)

### Picker agrupado — `app/workout/quick/page.tsx`
No `step === 1`, troque o bloco que mapeia `MODALITY_OPTIONS` em `SelectCard` por:
```tsx
import { ModalityPicker } from "./modality-picker";
// ...
{step === 1 && (
  <ModalityPicker
    value={modality}
    onSelect={(m) => { setModality(m); next(); }}
  />
)}
```
(Os valores de `Modality` são os mesmos do seu arquivo — `musculacao`, `bike`, etc.)

### Ambiente + Equipamentos — `app/workout/quick/page.tsx`
Adicione estado:
```tsx
const [equipment, setEquipment] = useState<EquipId[]>([]);
const [branchAnswer, setBranchAnswer] = useState<boolean | null>(null);
```
No `step === 3`, troque o grid de `LOCATION_OPTIONS` por:
```tsx
import { EnvironmentStep, type EquipId } from "./environment-step";
// ...
{step === 3 && modality && (
  <>
    <EnvironmentStep
      modality={modality}
      location={location}
      equipment={equipment}
      branchAnswer={branchAnswer}
      onLocation={(l) => { setLocation(l); setBranchAnswer(null); }}
      onToggleEquip={(e) => setEquipment((arr) => arr.includes(e) ? arr.filter(x=>x!==e) : [...arr, e])}
      onBranch={setBranchAnswer}
      onSwapModality={(m) => { setModality(m); setBranchAnswer(null); }}
    />
    <button
      className="..."  /* seu botão Continuar existente */
      disabled={!location}
      onClick={next}
    >Continuar →</button>
  </>
)}
```
E inclua `equipment` (e, se quiser, a resposta condicional) no corpo do POST em `generate()`:
```tsx
await api.post("/api/v1/quick_workouts", {
  modality, duration_minutes: duration, location, difficulty: selectedDifficulty,
  equipment,                       // ← novo
});
```
> Backend: aceitar `equipment` (array) p/ refinar a geração. Enquanto o backend
> não usa, o front já captura — sem quebrar nada.

---

## SPEC 7 — Gerenciar treino agrupado (cardio/interval)
Hoje o modal "Gerenciar treino" lista exercícios. Para modalidades de
cardio/interval, agrupar em ciclos (igual ao protótipo):

- Detectar engine via `workoutEngine(ex)`. Se a maioria for `cardio`/`interval`:
  - Mostrar um card "**N ciclos**" + linhas "**Xs trabalho / Ys descanso**".
  - Edição: steppers de nº de ciclos, duração de trabalho, duração de descanso,
    intensidade (Leve/Média/Alta).
  - Persistir mapeando ciclos → exercícios (cada par trabalho/descanso = blocos).
- Para `strength`/`recovery`: manter a lista atual.
Referência: tela "Gerenciar treino" do protótipo (`pro-modes.css` seções
`.cycle-card`, `.edit-row`).

## SPEC 8 — Treinos (lista)
Seu `ChooseScreen` já tem A/B/C + últimos 7 dias. Alinhar ao protótipo:
- Topo: "Treino Rápido" + "Replanejar com IA".
- Hero "Treino de hoje" (card destacado) com "Iniciar treino".
- Lista "Meu plano" (badge = nome), "Favoritos & mais usados", "Histórico recente".
Referência: tela Treinos do protótipo (`renderPlan` / `.tr-*` no `pro-modes.css`).

---

## Validação geral
- Quick → passo 1 agrupado; Bike em "Casa" pergunta esteira e sugere troca.
- Execução de Bike/HIIT/Mobilidade com os painéis ricos; Musculação intacta.
- Gerenciar treino de um cardio mostra ciclos agrupados.
- Tudo herdando os tokens do `globals.css` (claro/escuro).
