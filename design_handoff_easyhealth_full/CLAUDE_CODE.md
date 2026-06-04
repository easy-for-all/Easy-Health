# CLAUDE_CODE.md — script pronto pra colar

Este arquivo tem **o prompt que você cola no Claude Code** (dentro do seu repositório, no VS Code)
para implementar o design da EasyHealth com **máxima fidelidade**, adaptando ao seu codebase.

## Como usar

1. Copie a pasta inteira `design_handoff_easyhealth_full/` para a **raiz do seu repositório**
   (ou qualquer lugar que o Claude Code consiga ler).
2. Abra o repositório no **VS Code** com o **Claude Code**.
3. Abra `prototype/EasyHealth Pro.html` no navegador pra ver o alvo enquanto o Claude trabalha.
4. **Cole o bloco abaixo** no Claude Code e siga o plano que ele propor.

> Dica: implemente **em fases** (uma mensagem por fase). Não peça tudo de uma vez — a fidelidade
> cai quando o escopo é grande demais por turno. As fases já estão numeradas no prompt.

---

## ⤵️ COLE ISTO NO CLAUDE CODE

````
Você vai implementar o redesign do app EasyHealth no NOSSO codebase, com a MAIOR
fidelidade visual e de comportamento possível ao protótipo de referência.

## Referência
Na pasta `design_handoff_easyhealth_full/` tem:
- `README.md` — documentação completa (tokens, telas, componentes, comportamentos). LEIA INTEIRO.
- `prototype/` — protótipos HTML/CSS/JS de ALTA FIDELIDADE, rodáveis no navegador.
  - `EasyHealth Pro.html` (+ `pro*.css/js`, `coach*.css/js`) = ESTADO FINAL, direção "Lumen"
    (azul, dark). É a fonte da verdade do visual.
  - `app.html` (+ `app.css/js`, `theme.css/js`) = telas extras que o Pro não tem: login,
    onboarding de 5 passos, assinatura, perfil detalhado. Use o conteúdo/estrutura delas,
    mas re-skin pro visual Lumen final.
  - `landing.html` = landing de conversão.

## Regras de implementação (importante)
1. NÃO copie o HTML cru pra produção. RECRIE cada tela usando os componentes, tokens e
   padrões que JÁ EXISTEM no nosso codebase. Se algo não existir no nosso DS, crie um
   componente novo seguindo as convenções do repo.
2. Fidelidade = estrutura, layout, hierarquia, espaçamento, estados (hover/active/sel),
   animações e microinterações batendo com o protótipo. Onde o README dá valor exato
   (oklch/px/ms), use-o como referência de origem.
3. CORES E TIPOGRAFIA: adapte para o NOSSO design system. Mapeie cada token do protótipo
   (--bg, --surface, --primary, --good, --hot, --warn, raios, sombras) pro equivalente do
   nosso DS. Só use os valores oklch do README onde não houver equivalente nosso.
4. NÃO recrie os andaimes de protótipo: device bezel, status bar fake, seletor de direções
   (theme.js) e painel de Tweaks (tweaks-panel.jsx / pro-tweaks.jsx). Ignore.
5. Texto do produto é pt-BR. Mantenha as copies do protótipo salvo instrução contrária.
6. Imagens/vídeos de exercício e fotos de pessoas são placeholders → deixe slots/placeholders
   no nosso padrão pra mídia real. Depoimentos da landing são fictícios.

## Antes de escrever qualquer código (FAÇA PRIMEIRO)
A. Detecte e me diga: framework, linguagem, gerenciador de estado, roteamento, lib de UI/
   styling (CSS-in-JS? Tailwind? tokens?), e onde ficam os componentes compartilhados.
B. Liste os tokens/temas que já temos e proponha o MAPEAMENTO token-do-protótipo → token-nosso
   (tabela). Aponte gaps (ex.: não temos cor de "warn").
C. Proponha a arquitetura de telas/rotas e a lista de componentes reutilizáveis a criar/reusar
   (veja a seção "Componentes recorrentes" do README).
D. Me apresente esse plano e ESPERE meu OK antes de codar a Fase 1.

## Fases (implemente uma por vez, pedindo revisão entre elas)
FASE 0 — Fundação: tokens/tema (mapeados pro nosso DS), tipografia (Bricolage Grotesque display +
  Hanken Grotesk corpo, ou nossos equivalentes), e os componentes base: Button, Card, Eyebrow,
  TagChip, Segmented, OptionCard, Slider, Stepper, ProgressDots, Toast.
FASE 1 — AgentOrb: o componente do orb do Coach (4 tamanhos: fab/lg/md/sm; props pulse, glyph ✦),
  com o gradiente radial e o glow do README §7. Reusável em todos os contextos.
FASE 2 — Loop de treino do Pro: telas `dashboard`, `plan`, `day`, `exec`, `done`.
  `exec` precisa do timer, barra de progresso, steppers carga/reps, séries, RPE e o
  overlay de descanso (ring + countdown).
FASE 3 — Criação de plano por IA: `create-goal/place/method/time` + `generating` (orb + etapas
  que completam em sequência).
FASE 4 — Progresso/Histórico: `history` (abas Resumo/Cargas/Histórico), gráfico de barras,
  equilíbrio muscular, timeline, e `progress-detail` (gráfico de linha + sugestão da IA).
  A lógica de geração de gráficos está em `prototype/pro-charts.js`.
FASE 5 — Favoritos e Perfil: `favorites`, `profile` (readiness ring, DNA de treino).
FASE 6 — Coach EasyHealth (agente): folha bottom-sheet, balões (usuário/IA/digitando), chips
  contextuais por tela, input auto-crescente, e o FLUXO DE TROCA DE EXERCÍCIO (3 cards de
  alternativa → tocar aplica a troca na tela de execução). Especificação em README §7 e nos
  arquivos `coach.js` / `coach-data.js`.
  - Integração de IA: NÓS temos/teremos uma API de LLM. Crie uma camada `aiClient` com a mesma
    forma de `window.claude.complete({messages})`, mas chamando NOSSO endpoint. Use a persona,
    o buildChatPrompt/buildSwapPrompt e o fallback de `coach.js` como especificação. Deixe a
    URL/credencial em config/env, não hardcoded.
FASE 7 — Telas de entrada/extra (do app.html, re-skin Lumen): `login`, onboarding 5 passos
  (`ob-goal/level/body/activities/place`), `profile-detail`, assinatura (`plan`).
FASE 8 — Landing page (de `landing.html`), responsiva mobile+desktop.

## Qualidade
- Acessibilidade: role="dialog" na folha, aria-label nos botões de ícone, foco gerenciado,
  prefers-reduced-motion desligando pulsos, hit targets >= 44px.
- Sem libs novas pesadas sem me perguntar. Reuse o que já temos.
- Ao fim de cada fase: me diga o que fez, o que ficou pendente, e como testar.

Comece pelo passo A–D (detecção + plano) e me peça OK.
````

---

## Variações do prompt (opcional)

- **Só o Pro (sem landing/app demo):** apague as FASES 7 e 8 e a menção a `app.html`/`landing.html`.
- **Sem o Coach de IA por enquanto:** apague a FASE 6 e o AgentOrb pode virar só decorativo.
- **Fidelidade pixel-perfect (ignorar nosso DS):** troque a Regra 3 por "Use EXATAMENTE os tokens
  oklch do README; não adapte" — só faça isso se o app ainda não tiver design system.

## Checklist de aceite (cole depois, pra validar)

````
Compare a implementação com prototype/EasyHealth Pro.html e me dê um relatório por tela:
o que está fiel, o que divergiu (cor/spacing/tipo/estado/animação) e por quê. Liste
qualquer token que você teve que inventar por falta de equivalente no nosso DS.
````
