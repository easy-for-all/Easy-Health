# Handoff EasyHealth — projeto completo (landing + app demo + Pro)

> **Para o desenvolvedor / Claude Code:** os arquivos em `prototype/` são **referências
> de design de ALTA FIDELIDADE** feitas em HTML/CSS/JS vanilla. **Não é pra subir esse HTML
> em produção.** A tarefa é **recriar esses designs dentro do codebase existente**, usando
> os componentes, tokens e padrões que já existem lá. Onde este doc dá um valor exato
> (oklch / px / ms), respeite-o.
>
> O passo a passo de execução está em **`CLAUDE_CODE.md`** (o "script" pronto pra colar).

---

## 0. Como rodar a referência

Abra qualquer um destes no navegador (é só HTML estático, sem build):

| Arquivo | O que é |
|---|---|
| `prototype/index.html` | **Hub** de revisão — links pra landing e pro app, e explicação das 3 direções visuais. |
| `prototype/landing.html` | **Landing page** de conversão (responsiva, mobile + desktop). |
| `prototype/app.html` | **App demo** — onboarding completo + loop de treino, num frame de celular. Suporta as **3 direções** (Voltagem/Lumen/Pulse) × claro/escuro pelo seletor ⚙ no canto. |
| `prototype/EasyHealth Pro.html` | **App Pro** — a versão **mais refinada e final**, comprometida com a direção **Lumen (azul)**, dark-only. Inclui o **Coach EasyHealth** (agente de IA conversacional). É o estado-alvo de maior fidelidade. |

> Seletor de tema flutuante (⚙ canto inf. direito) só existe em `index/landing/app`. O **Pro**
> é dark-only e ajusta acento/raio/fonte via painel de **Tweaks** (que **não** faz parte do
> produto — ignore na implementação).

---

## 1. Visão geral do produto

EasyHealth é um app de treino com IA. O fluxo end-to-end:

```
Landing (aquisição)
   └─► Login / Cadastro
         └─► Onboarding (objetivo → nível → dados físicos → atividades → local)
               └─► Geração de plano por IA (tela animada)
                     └─► Dashboard (treino do dia, ofensiva/streak, plano)
                           ├─► Lista de treinos → Detalhe → Aquecimento → Treino ATIVO → Concluído
                           ├─► Progresso / Histórico (métricas, gráficos, evolução de carga)
                           ├─► Favoritos (alimentam a IA)
                           ├─► Perfil / Perfil detalhado (IMC, TMB)
                           └─► Assinatura (Pro mensal / anual)
   └─► Coach EasyHealth (agente de IA) — acessível por FAB em todas as telas do Pro
```

Idioma do produto: **pt-BR**. Persona masculina de exemplo: "Marcus".

---

## 2. Fidelidade

**Alta fidelidade (hifi).** Cores, tipografia, espaçamentos, raios, sombras, brilhos e
transições estão finalizados nos arquivos `prototype/`. O **EasyHealth Pro.html** é a fonte
da verdade do visual final; o `app.html` é a versão multi-direção mais antiga (útil pra ver
telas que o Pro não tem: login, onboarding de 5 passos, assinatura, perfil detalhado).

**Decisão deste handoff (definida pelo time):** *adaptar ao design system existente do codebase.*
Ou seja — **recrie a estrutura, layout, hierarquia e comportamento fielmente**, mas mapeie cores/
tipografia/raios pros **tokens que já existem no seu app**. Os valores oklch abaixo são a
referência de origem (use-os só onde o codebase não tiver equivalente).

---

## 3. Design tokens (referência de origem)

### 3.1 Direção final do Pro — "Lumen" (dark)

Fonte: `prototype/pro.css`. oklch é a verdade; hex é aproximação.

| Token | oklch | ~hex |
|---|---|---|
| `--bg` (fundo app) | `oklch(0.155 0.022 262)` | `#0f1320` |
| `--bg-2` (campo/folha) | `oklch(0.185 0.026 262)` | `#151a29` |
| `--surface` (cards) | `oklch(0.213 0.028 262)` | `#1b2031` |
| `--surface-2` (hover) | `oklch(0.255 0.030 262)` | `#222840` |
| `--surface-3` | `oklch(0.300 0.032 262)` | `#2b3250` |
| `--text` | `oklch(0.975 0.008 258)` | `#f4f5fb` |
| `--text-muted` | `oklch(0.755 0.018 262)` | `#aab0c4` |
| `--text-dim` | `oklch(0.585 0.020 262)` | `~#7a8199` |
| `--text-faint` | `oklch(0.46 0.020 262)` | — |
| `--border` | `oklch(0.315 0.026 262)` | `#2e3450` |
| `--border-strong` | `oklch(0.40 0.032 262)` | `#3e466a` |
| `--primary` (acento) | `oklch(0.685 0.17 258)` | `#6a78ee` |
| `--primary-2` | `oklch(0.605 0.17 264)` | `#5a5fd6` |
| `--primary-soft` | `oklch(0.685 0.17 258 / .14)` | primary @ 14% |
| `--on-primary` (texto s/ azul) | `oklch(0.985 0.01 258)` | `#fafaff` |
| `--good` (sucesso) | `oklch(0.78 0.16 158)` | `#34c98a` |
| `--good-soft` | `oklch(0.78 0.16 158 / .16)` | — |
| `--warn` (amarelo) | `oklch(0.82 0.15 78)` | `#e8b23e` |
| `--warn-soft` | `oklch(0.82 0.15 78 / .16)` | — |
| `--hot` (vermelho/❤) | `oklch(0.70 0.19 28)` | `#f2674e` |
| `--hot-soft` | `oklch(0.70 0.19 28 / .16)` | — |
| `--cool` | `oklch(0.78 0.12 232)` | — |

> O acento do Pro é **derivado de um matiz** `--accent-h` (default 258) + croma `--accent-c`
> (0.17): `--primary: oklch(0.685 var(--accent-c) var(--accent-h))`. Trocar 1 variável muda o
> app inteiro. Mantenha esse padrão se o seu DS permitir.

### 3.2 As 3 direções da landing/app demo

Fonte: `prototype/theme.css`. Cada direção tem variante **light** e **dark**. Acento de cada uma:

| Direção | Vibe | Fonte display | `--primary` (dark) |
|---|---|---|---|
| **a · Voltagem** (default) | Atlético, neon lima | Archivo | `oklch(0.88 0.20 128)` (lima) |
| **b · Lumen** | Premium, azul editorial | Bricolage Grotesque | `oklch(0.68 0.18 262)` (azul) |
| **c · Pulse** | Amigável, violeta+coral | Space Grotesk | `oklch(0.66 0.19 290)` (violeta), accent coral `oklch(0.74 0.17 40)` |

> Para o produto final, **o time escolheu Lumen** (= a base do `EasyHealth Pro.html`). As outras
> duas direções são material de exploração; só recrie o seletor de direções se você quiser manter
> a capacidade de tematização. Caso contrário, implemente direto em Lumen.

### 3.3 Tipografia

- **Display/títulos (Pro/Lumen):** Bricolage Grotesque, 700/800, `letter-spacing: -0.02em`.
- **Corpo:** Hanken Grotesk (400–800).
- **Mono** (labels de placeholder/medidas): Geist Mono.
- **Números grandes** (carga, timer, métricas): fonte display + `font-variant-numeric: tabular-nums`.
- Outras direções: Voltagem → Archivo; Pulse → Space Grotesk.
- Carregamento das fontes: ver `prototype/fonts.css` (Google Fonts). No app real, prefira
  self-host / o pipeline de fontes do seu codebase.

Escala de títulos (Pro): `--h-xl 33px` · `h-lg 26px` · `h-md 20px` · `h-sm 17px`.
`eyebrow` = 11.5px, weight 800, `letter-spacing .16em`, uppercase, cor `--text-dim`.

### 3.4 Raio, sombra, easing

```css
/* raio — multiplicável por --radius-scale (default 1) */
--r-xs 8px · --r-sm 12px · --r-md 18px · --r-lg 24px · --r-xl 32px · --r-pill 999px

--shadow:    0 18px 44px -22px rgba(0,0,0,.8);
--shadow-lg: 0 40px 90px -40px rgba(0,0,0,.9);
--glow: 0 0 0 1px oklch(.685 .17 258 / .35), 0 12px 40px -10px oklch(.685 .17 258 / .45);

--ease:     cubic-bezier(.22, 1, .36, 1);
--ease-out: cubic-bezier(.16, 1, .3, 1);
```

Timings-chave: entrada de tela (stagger `rise` .5s, delays .02→.22s) · folha do chat sobe
.42s · descanso/animações de IA conforme CSS.

---

## 4. O frame de celular (prototype only)

Os apps são mostrados num **device frame** de 402×872 (`.stage` → `.device` → `.screen-frame`),
com status bar fake e tab bar. **Isso é andaime de protótipo** — no app real, as telas ocupam a
viewport nativa. Não recrie o bezel; recrie só o conteúdo de cada `.screen`.

Cada tela é uma `<section class="screen" data-screen="..." data-screen-label="..." data-chrome="full|none" data-tab="...">`.
`data-chrome="none"` = sem tab bar (telas de fluxo: onboarding, execução). `data-chrome="full"` =
com tab bar + FAB. Use isso pra mapear quais telas são rotas com navegação inferior vs. fluxos modais.

---

## 5. Telas (inventário completo)

### App demo (`app.html`) — onboarding + loop base
| `data-screen` | Tela | Pontos-chave |
|---|---|---|
| `login` | Login / boas-vindas | Logo glyph "E", e-mail+senha, "Criar conta grátis" → onboarding. |
| `ob-goal` | Onboarding 1 — objetivo | Opções single-select (Perder peso / Ganhar músculo / Manter / Saúde geral). Stepper de progresso (5 dots). |
| `ob-level` | Onboarding 2 — nível | Iniciante / Intermediário / Avançado. |
| `ob-body` | Onboarding 3 — dados físicos | Segmented (gênero) + 3 sliders (idade/peso/altura) com valor ao vivo. |
| `ob-activities` | Onboarding 4 — atividades | Grid multi-select com emoji (Musculação, Cardio, …). |
| `ob-place` | Onboarding 5 — local | Academia / Em casa / Ao ar livre / Varia. |
| `generating` | Geração por IA | Orb pulsante + lista de etapas que completam em sequência. |
| `dashboard` | Dashboard | Hero "treinar agora", card de ofensiva/streak semanal, lista de treinos, card Personal IA. |
| `list` | Escolha de treino | Filtros (Todos/Favoritos), linhas de treino, histórico 7 dias. |
| `detail` | Detalhe do treino | Lista de exercícios, descanso, "iniciar treino". |
| `warmup` | Aquecimento | Lista numerada de movimentos. |
| `active` | **Treino ativo** | Timer funcional, barra de progresso, mídia+mapa muscular, contadores (séries/reps/peso), "Feito — série X/Y". |
| `done` | Concluído | Confete, stats (min/volume/exercícios/kcal), resumo, nível de cansaço (rate 1–5). |
| `profile` | Perfil | Header, mini-stats, dados físicos, lista de ajustes, toggle de tema. |
| `profile-detail` | Perfil detalhado | IMC, peso ideal, TMB, água corporal; upload de fotos/exames. |
| `plan` | Assinatura | Pro Mensal R$19,90 / Pro Anual R$118,80 (≈50% off), 7 dias grátis. |

### App Pro (`EasyHealth Pro.html`) — estado final, com IA-first
| `data-screen` | Tela | Pontos-chave |
|---|---|---|
| `dashboard` | Dashboard Pro | Saudação + avatar, **hero do próximo treino** (Upper·Força), card **Coach EasyHealth** (insight do dia), streak da semana, lista do plano de hoje, "criar objetivo". |
| `create-goal` | Criar plano 1/4 — objetivo | Wizard com a IA montando a estratégia. |
| `create-place` | Criar plano 2/4 — local/equipamentos | Single (local) + multi (equipamentos). |
| `create-method` | Criar plano 3/4 — método | "Deixar a IA decidir" (recomendado) ou escolher método. |
| `create-time` | Criar plano 4/4 — tempo/frequência | Sliders (dias/semana, min/treino), segmented intensidade, campo de restrições. |
| `generating` | IA gerando | Orb grande + 6 etapas que completam. |
| `plan` | Plano gerado | Resumo (objetivo/método/nível/duração), bloco **"Por que este treino foi criado assim?"**, semana, dias de treino. |
| `day` | Detalhe do dia | Nota do coach, lista de exercícios reordenável, adicionar exercício, iniciar. |
| `exec` | **Execução** | Progresso, mídia + mapa muscular, ações (vídeo/como fazer/**trocar**), comparação de carga (última vs sugestão), steppers carga/reps, séries, **RPE** (fácil/ok/pesado), **overlay de descanso** com ring + timer. |
| `done` | Concluído | Confete, stats (min/volume/exercícios/+%), "o que o coach registrou", resumo, nível de cansaço. |
| `history` | Progresso | Abas Resumo/Cargas/Histórico: métricas, gráfico de barras, equilíbrio muscular, timeline. |
| `progress-detail` | Evolução de carga | Gráfico de linha de carga, métricas, **sugestão da IA** pro próximo treino. |
| `favorites` | Favoritos | Explica que favoritos alimentam a IA; lista de exercícios e treinos favoritos. |
| `profile` | Perfil fitness | Header + readiness ring, mini-stats, **"DNA de treino"**, card "plano ativo", lista de config. |

### Landing (`landing.html`)
Hero com mockup do app, recursos, "como funciona" com mockups, prova social (depoimentos
**fictícios** — placeholder), planos. Responsiva mobile+desktop. Imagens de pessoas/exercícios
são **placeholders listrados marcados** — substituir pelas reais.

---

## 6. Componentes recorrentes (recriar como componentes reutilizáveis)

Mapeie cada um pro equivalente no seu DS:

- **Botões:** `.btn` (pill, 16/22px) com variantes `btn-primary` (gradiente azul + glow),
  `btn-ghost`, `btn-outline`, `btn-light`, `.sm`. `:active { scale(.985) }`.
- **Cards:** `.card` (raio lg, surface, border). Variantes `card-soft` (gradiente do acento) e
  `card-glass` (blur).
- **Eyebrow / tag-chip / ai-pill** (rótulos e badges).
- **Option cards** (`.opt`, `.opt-grid`) — selecionáveis com check; single e multi.
- **Segmented control** (`.seg`) e **seg-tabs** (abas internas).
- **Slider** (`input[type=range]`) com thumb custom (branco, borda azul, glow) + valor ao vivo.
- **Stepper** numérico (carga/reps).
- **Progress dots** do wizard (`.prog`).
- **Workout row** (`.wkt`/`.wkt-row`), **exercise row** (`.exrow`), **day pills**.
- **Hero do treino** (gradiente do acento + ring decorativo).
- **Streak/semana** (dots por dia, "today"/"done").
- **Métricas, gráfico de barras, sparkline, timeline, barras de equilíbrio muscular**
  (ver `prototype/pro-charts.js` para a lógica de geração).
- **Readiness ring**, **profile head**, **mini-stats**, **list-card**.
- **Media placeholder listrado** (`.media-ph`) — onde entram foto/vídeo do exercício; o label
  mono diz o que vai ali. **Substituir por mídia real.**
- **Toast**, **rest overlay**, **confetti**.
- **FAB** — ver §7 (é o orb do agente).
- **Tab bar** — navegação inferior (Pro: Hoje/Plano/Progresso/Favoritos/Perfil).

> Não recrie o **device bezel**, o **status bar fake**, o **seletor de direções** (`theme.js`)
> nem o **painel de Tweaks** (`tweaks-panel.jsx`/`pro-tweaks.jsx`) — são andaimes de protótipo.

---

## 7. Coach EasyHealth (agente de IA) — peça central do Pro

A identidade do agente é o **ORB**: esfera com gradiente radial azul + ✦ branco + glow neon.
A MESMA esfera em 4 tamanhos/contextos. Recrie como **um componente** (`<AgentOrb size pulse glyph/>`).

```css
/* gradiente idêntico em todos os tamanhos */
background: radial-gradient(circle at 36% 30%,
  oklch(0.88 0.10 258),   /* realce */
  var(--primary) 46%,
  var(--primary-2) 82%);
border-radius: 50%;
box-shadow: 0 0 0 1px oklch(.685 .17 258 / .4), 0 0 22px oklch(.685 .17 258 / .55);
```

Ícone ✦ (sparkles), branco, stroke ~2px, fill none:
```
<path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6L12 3z"/>
<path d="M19 14l.7 1.9L21.6 17l-1.9.7L19 19.6l-.7-1.9L16.4 17l1.9-.7L19 14z"/>
```

| Contexto | Tamanho | ✦ | Pulso | Onde |
|---|---|---|---|---|
| FAB | 58px | sim 25px | anel 2.6s | canto inf. dir., todas as telas |
| Header do chat | 46px | não | não | topo da folha |
| Avatar de balão IA | 28px | não | quando "pensando" 1.4s | ao lado das msgs do coach |
| Avatar de card | 34–36px | sim | não | cards onde o coach "fala" |

Respeite `@media (prefers-reduced-motion: reduce)` desligando pulsos.

**Onde o orb aparece como "o coach fala" (avatar de card):** Dashboard (insight do dia),
Plano gerado ("Por que este treino…"), Detalhe do dia ("Nota do coach"), Concluído ("O que o
coach registrou"), Evolução de carga ("Sugestão pro próximo treino"), Perfil ("Plano ativo").

### 7.1 Folha do chat (bottom sheet)
Sobe sobre a tela (não troca rota). Estrutura: scrim com blur → folha 88% altura, cantos
superiores `--r-xl` → header (orb 46px + "Coach EasyHealth" + status "● IA · responde em tempo
real" + fechar) → body (balões, gap 14px) → badge de contexto (só na execução) → chips de ações
rápidas (mudam por tela) → input (textarea auto-crescente + enviar 38px). Sobe em .42s.

**Balões:** coach = orb 28px + balão `--surface`, raio 20px com canto inf. esq. 7px; usuário =
gradiente azul à direita, `--on-primary`, canto inf. dir. 7px, com glow. "Digitando" = 3 pontos.

### 7.2 Chips por contexto
- **Execução:** "Outra opção pra esse exercício", "Tá pesado demais", "Como executar certo?".
- **Criação/plano:** "Treino de 30 min", "Foca em peito hoje", "Sem equipamento".
- **Demais:** "Como tá minha evolução?", "Treino de hoje", "O que treino amanhã?".

### 7.3 Fluxo-chave: troca de exercício na execução
1. Usuário toca "Trocar" / o FAB / digita o pedido.
2. Folha abre com balão do usuário.
3. Coach responde 1 frase curta + **3 cards de alternativa** (thumb, nome, motivo, tag, séries×reps·carga, botão +).
4. Tocar num card **aplica a troca na tela de execução** (substitui exercício, recarrega carga/séries),
   marca o card como aplicado (verde ✓), esmaece os outros, posta confirmação com "Ver na tela do treino →".

Detecção de intenção (regex `isSwapIntent` em `coach.js`): "outra opção", "trocar", "substituir",
"não gostei", "alternativa" → dispara o fluxo em vez de resposta de texto.

Hooks expostos pelo protótipo (em `pro-app.js`): `EH.execContext()` → `{idx,total,exercise,set}`;
`EH.applySwap(alt)` → aplica a troca. Pool de alternativas: `EH.altPool` + `EH.alternativesFor(ex)`
em `coach-data.js`.

---

## 8. Integração com IA (real)

O protótipo chama um LLM via `window.claude.complete({ messages:[{role,content}] })`. **No seu
codebase, troque pela SUA API de LLM** (o time confirmou que terá uma).

- **Persona/sistema:** "Coach EasyHealth, personal trainer de IA. Tom técnico e objetivo, foco em
  dados e progressão. PT-BR. Máx. 3 frases curtas e práticas. Cita carga/reps/séries/descanso
  quando ajuda. Máx. 1 emoji. Sem títulos/listas longas. Não inventa lesões." + **perfil do aluno**
  (objetivo, nível, método, frequência, favoritos, grupos atrasados — `EH.coachProfile()`).
- **Contexto por turno:** tela atual + (na execução) exercício/série em foco.
- **Histórico:** últimos ~6 turnos.
- **Modo "intro de troca":** pede só 1 frase (os exercícios vêm nos cards).
- **Fallback offline:** respostas de reserva coerentes (`fallbackAnswer` em `coach.js`).

Toda a lógica de prompt está em `coach.js` (`persona`, `buildChatPrompt`, `buildSwapPrompt`,
`callAI`) — use como especificação do que mandar pro seu modelo.

---

## 9. Estado necessário (independente de framework)

- `coachOpen`, `messages[]`, `busy`, `lastAlternatives[]`, `currentScreen`.
- **Sessão de treino:** lista de exercícios + índice atual + série atual + carga/reps. A troca de
  exercício escreve nesse estado; a tela de execução reage.
- **Onboarding/criação:** objetivo, nível, gênero, idade/peso/altura, atividades, local, equipamentos,
  método, dias/semana, min/treino, intensidade, restrições.
- **Perfil:** stats agregadas (treinos, streak, aderência, volume, equilíbrio muscular).
- **Favoritos:** exercícios e treinos (priorizam geração de plano).

---

## 10. Conteúdo / placeholders

- Fotos de pessoas e mídias de exercício são **placeholders listrados marcados** → substituir por reais.
- Depoimentos da landing são **fictícios** (ilustram layout).
- Números (volume, kcal, %s, kg) são mock — vêm do backend no app real.
- Preços de assinatura: Pro Mensal **R$ 19,90/mês**, Pro Anual **R$ 118,80/ano** (≈ R$ 9,90/mês),
  7 dias grátis. (Confirme com o time antes de cravar.)

---

## 11. Acessibilidade

- Folha = `role="dialog"`; foco no input ao abrir (exceto quando abre já no fluxo de troca).
- `aria-label` em botões de ícone (fechar, enviar, favoritar).
- Respeitar `prefers-reduced-motion` (desliga pulsos/entradas).
- Hit targets ≥ 44px. Contraste de texto sobre azul usa `--on-primary`.

---

## 12. Arquivos em `prototype/`

**Pro (estado final — prioridade):**
- `EasyHealth Pro.html` — todas as telas do Pro.
- `pro.css` — sistema Lumen (tokens, botões, FAB orb, base).
- `pro-screens.css` — componentes de tela (hero, insight, exec, gráficos, perfil, avatares orb).
- `pro-app.js` — roteador/render + hooks `EH.execContext` / `EH.applySwap` + dados.
- `pro-data.js`, `pro-charts.js` — dados mock e geração de gráficos.
- `coach.css` ⭐ — folha do chat, balões, cards de alternativa, chips, input.
- `coach.js` ⭐ — lógica do agente (abrir/fechar, contexto, chips, IA, intenção/aplicar troca, fallback).
- `coach-data.js` ⭐ — pool de alternativas por músculo, perfil resumido, rótulos.

**App demo + landing (telas extras: login, onboarding, assinatura, perfil detalhado):**
- `app.html`, `app.css`, `app.js`.
- `landing.html`.
- `index.html` — hub de revisão.
- `theme.css`, `theme.js`, `fonts.css` — sistema das 3 direções + fontes.

**Ignorar (andaime de protótipo):** `tweaks-panel.jsx`, `pro-tweaks.jsx`, o device bezel,
o status bar fake e o seletor de direções.

---

Ver **`CLAUDE_CODE.md`** para o passo a passo de implementação pronto pra colar.
