# Design Brief — Repaginação EasyHealth

**Projeto:** EasyHealth  
**Audiência deste documento:** Claude Design / Designer  
**Objetivo:** Reformular o design da home (landing page), fluxo de onboarding e tela de cadastro para reduzir bounce e aumentar conversão.

---

## 1. O que é a EasyHealth

Webapp SaaS de treino inteligente com IA. O usuário responde um onboarding rápido (5 passos) e recebe um plano de treino semanal personalizado. A cada dia, ele vê o treino do dia, executa, registra cargas e acompanha a evolução. A IA sugere trocas de exercício e adapta o plano com base no feedback.

**Planos:** Free (7 dias) → Pro Mensal R$19,90 → Pro Anual R$9,90/mês  
**Stack:** Next.js + React + TypeScript + Tailwind CSS  
**Cor primária atual:** azul (primary-500 ~`#3b82f6`)  
**Mobile-first:** sim, o produto é majoritariamente usado no celular

---

## 2. Problema principal (negócio)

Usuários chegam via **Google AdSense/anúncios pagos** e **abandonam a landing page sem converter**. Taxa de bounce alta. Os diagnósticos:

1. **Proposta de valor não é imediata** — o usuário precisa rolar para entender o que a EasyHealth faz
2. **A home não é visualmente atrativa** — parece um template genérico, sem identidade ou emoção
3. **Nenhum prova social convincente** — só uma frase de um usuário (sem foto, sem credibilidade)
4. **O CTA não é urgente o suficiente** — "Criar conta" não cria desejo
5. **Onboarding genérico** — parece um formulário, não uma experiência que anima o usuário
6. **Sign-up sem contexto** — após a landing, a tela de cadastro perde toda a narrativa do produto

---

## 3. Fluxo atual (completo)

```
Landing page (/)
  ↓ clica em "Criar conta"
Sign-up (/sign-up)
  ↓ cria conta
Onboarding (/onboarding)
  Step 1: Objetivo (4 opções)
  Step 2: Nível de condicionamento (3 opções)
  Step 3: Dados físicos (gênero + sliders de idade/peso/altura)
  Step 4: Atividades preferidas (grid de 7 atividades)
  Step 5: Local de treino (4 opções)
  ↓ salva no backend → redireciona para /plan
Plano semanal (/plan)
```

---

## 4. Análise tela por tela

### 4.1 Landing Page (`/`)

**Estrutura atual:**
- Header fixo: logo + "Preços" + "Entrar" + "Criar conta"
- Hero: badge + H1 + subtítulo + 2 CTAs + 1 depoimento
- Seção "O que a EasyHealth faz": 6 feature cards (links para páginas de SEO)
- Seção "Como funciona na prática": 6 cards mockup do produto (estático, hardcoded)
- Seção "Feito para quem quer evoluir": 3 pilares
- CTA final: banner azul + botão
- Footer

**Problemas específicos:**
- O hero tem dois CTAs concorrendo ("Começar" e "Ver como funciona") — dispersa o foco
- Badge "Mais de 500 treinos gerados" é fraco como prova social
- O H1 ("Treino inteligente com IA para evoluir com mais constância") é genérico, não diferencia
- Nenhuma imagem real do produto — o usuário não sabe como é a interface
- Os 6 feature cards são links para páginas de SEO (não é o produto em si) — confuso para o usuário que veio de anúncio
- Depoimento de "Lucas M." sem foto, sem contexto — não cria confiança
- A seção "Como funciona na prática" com 6 cards é boa em conceito, mas visual muito denso
- Falta uma âncora visual clara de "antes vs. depois" — sem treino estruturado x com EasyHealth

### 4.2 Sign-up (`/sign-up`)

**Estrutura atual:**
- Tela centralizada simples: título "Criar conta" + subtítulo + form (nome, email, senha, checkbox termos) + botão

**Problemas específicos:**
- Toda a narrativa e energia da landing se perde aqui
- Não há reforço do valor — o usuário está no momento mais crítico de decisão e recebe um formulário vazio
- Não há indicação de "Você está a 2 minutos do seu plano personalizado"
- Sem prova social ou elemento de confiança no momento da conversão
- Checkbox de termos de uso bloqueante antes de qualquer valor entregue

### 4.3 Onboarding (`/onboarding`) — 5 steps

**Estrutura atual:**
- Barra de progresso no topo (5 segmentos)
- Step 1: Objetivo — 4 cards de seleção, avança automaticamente
- Step 2: Nível — 3 cards, avança automaticamente
- Step 3: Dados físicos — seleção de gênero + 3 sliders (idade/peso/altura) + botão Continuar
- Step 4: Atividades — grid 2 colunas com 7 opções + botão Continuar
- Step 5: Local de treino — 4 cards, selecionar já finaliza e cria o plano

**Problemas específicos:**
- Parece um formulário burocrático, não uma experiência
- Nenhum reforço positivo entre os steps ("Ótimo! Agora vamos...")
- A transição entre steps é abrupta — sem animação, sem celebração
- Step 3 (dados físicos) é o mais pesado: 4 inputs diferentes + sliders = fricção alta
- Os sliders de peso/altura no mobile são ruins de usar
- Não há sensação de progresso emocional — só a barra no topo
- O loading final ("Criando seu plano...") não tem feedback visual elaborado — oportunidade perdida
- Nenhuma preview do que vem depois ("Seu plano estará pronto em segundos")

---

## 5. O que o design precisa resolver

### Prioridade 1 — Landing Page

**Objetivo:** Fazer o usuário entender o produto em 5 segundos e querer clicar em "Começar".

Requisitos:
- Hero acima do fold deve comunicar: **o que é + para quem + prova que funciona**
- Visual do produto real ou mockup de alta fidelidade do app (treino do dia, evolução)
- Um único CTA principal no hero, sem concorrência
- Prova social com foto/avatar + nome + resultado concreto (ex: "Larissa perdeu 8kg em 3 meses")
- Seção "como funciona" em 3 passos simples (não 6 cards)
- Urgência/escassez suave: "7 dias grátis, sem cartão"
- Footer com links úteis e credibilidade (CNPJ, suporte, redes)

**Tom de voz:** Direto, motivador, sem jargão técnico. Fala de resultado, não de feature.

### Prioridade 2 — Onboarding

**Objetivo:** Tornar o onboarding uma experiência que anima, não uma burocracia.

Requisitos:
- Step de "boas-vindas" antes do step 1: "Vamos montar seu treino em 2 minutos" + preview do que vem
- Transições suaves entre steps (slide ou fade)
- Reforço positivo ao avançar ("Perfeito!" / "Quase lá!")
- Redesenhar o step de dados físicos: substituir sliders por pickers mais tácteis no mobile
- Loading final animado: "Criando seu plano personalizado..." com animação de 2–3s antes de redirecionar
- Mostrar preview do que será gerado no último step ("Seu treino de Peito + Tríceps está quase pronto")

### Prioridade 3 — Sign-up

**Objetivo:** Manter o momentum da landing, reduzir abandono no formulário.

Requisitos:
- Trazer de volta o benefício principal: "Seu plano personalizado em 2 minutos"
- Mostrar os 3 próximos passos: 1 → Criar conta · 2 → Onboarding · 3 → Começar a treinar
- Minimizar campos: nome + email + senha é o mínimo viável
- Mover o checkbox de termos para depois ou deixar em destaque menor
- Botão de CTA mais emocional: "Quero meu plano grátis" em vez de "Criar conta"

---

## 6. Referências de estilo e tom

**Concorrentes para benchmarking:**
- Whoop — design minimalista, métricas como destaque
- Freeletics — hero com resultado humano real, onboarding gamificado
- MyFitnessPal — simplicidade, foco no fluxo
- Duolingo — onboarding que motiva com progresso e personalidade

**Identidade atual:**
- Cor primária: azul (#3b82f6 aproximado, classe Tailwind `primary-500`)
- Fonte: padrão Next.js/Tailwind (Inter)
- Modo claro (padrão) + suporte a dark mode
- Bordas arredondadas generosas (rounded-xl, rounded-2xl)
- Sombras suaves (shadow-sm)

**Direção desejada:**
- Mais personalidade e energia — menos template SaaS genérico
- Imagens/ilustrações de pessoas reais treinando (ou mockups fotorrealistas do app)
- Hierarquia visual mais clara — o olho sabe onde ir primeiro
- Mobile-first rigoroso — a maioria dos usuários vem do anúncio no celular

---

## 7. Constraints técnicas

- Stack: Next.js + Tailwind CSS — o designer deve entregar layouts que possam ser implementados com utilitários Tailwind
- Não mudar o sistema de cores: `primary-*` (azul), `gray-*`, `green-*`, `orange-*`
- Sem bibliotecas pesadas de animação (pode usar Framer Motion, já instalado)
- Mobile-first breakpoints: `sm:` (640px), `md:` (768px), `lg:` (1024px)
- Imagens: não usar imagens de stock que precisem de licença paga; preferir mockups gerados ou fotos livres (Unsplash)
- Acessibilidade: manter contraste mínimo WCAG AA

---

## 8. O que NÃO mudar

- Fluxo de dados do onboarding (5 steps com os mesmos campos — só repaginar o visual)
- Campos do formulário de sign-up (nome, email, senha)
- Sistema de pricing (Free + Pro Mensal + Pro Anual)
- Estrutura de navegação (header, footer, bottom nav no app)
- Dark mode deve continuar funcionando

---

## 9. Entregáveis esperados

1. **Redesign da landing page** — wireframe de alta fidelidade + especificação de cores/espaçamentos
2. **Redesign do sign-up** — tela única repaginada
3. **Redesign do onboarding** — todos os 5 steps + tela de loading/finalização
4. **Guia de tom visual** — como usar os elementos de design (cards, botões, tipografia) de forma consistente

---

## 10. Prints enviados pelo produto

> Os prints de tela estão anexados à conversa. Analise:
> - Home atual: veja o hero, a seção de features e o CTA final
> - Onboarding atual: veja os 5 steps e a barra de progresso
> - Sign-up: veja o formulário atual
> - Interior do app (treino do dia, plano semanal): use como referência para mockups na landing

---

## 11. Métricas de sucesso (para guiar decisões de design)

- **Taxa de conversão da landing:** visitante → clique em "Criar conta" (meta: > 8%)
- **Completion rate do onboarding:** usuário que começa → chega no /plan (meta: > 70%)
- **Drop-off no sign-up:** meta < 30% de abandono após iniciar o formulário
- **Tempo no hero:** usuário deve entender o produto sem rolar (above the fold)

---

*Documento gerado em 2026-05-31. Qualquer dúvida sobre o produto ou stack, consultar o responsável pelo projeto: Marcus Reis.*
