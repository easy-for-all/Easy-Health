# Admin Dashboard — EasyHealth

## Estado atual (esta entrega)

O endpoint legado `GET /api/v1/admin/stats` foi **mantido** e corrigido:
- "Executou treino" = definição única (`completion_status="completed"`).
- Retenção D1/D7/D30 timezone-aware (`Analytics::ReportingTime`), base `User.reportable`,
  com `retention_detail` (numerador/denominador/status/cohort_maturity via `MetricResult`).
- Conversões clampadas a [0,100].

## Alvo (por domínio) — a construir

Endpoints por domínio sob `namespace :admin` (não um monólito), cada um retornando
`MetricResult` com `numerator`, `denominator`, `sample_size`, `status`, `cohort_maturity`,
`definition`, comparação de período e filtros (plataforma/app_surface/versão/período/
onboarding/assinatura/origem/experimento):

`overview` · `acquisition` · `activation` · `retention` · `workouts` · `onboarding` ·
`android` · `push` · `revenue` · `experiments` · `data_quality` · `users`.

## Abas do painel

1. **Visão Executiva** — novos, ativos 7d, Weekly Active Trainees, treinos iniciados/
   concluídos, Activation 24h, Habit 7d, retenção de valor D7, premium, conversão trial,
   comparação com período anterior. Períodos: hoje/7d/30d/custom.
2. **Aquisição e Plataformas** — cadastros por plataforma, app first opens, Android
   autenticados, Web only, PWA, cross-platform, distribuição por versão. Nota: first_open
   ≠ download.
3. **Ativação** — funil `signup_completed → onboarding_started → workout_created →
   workout_viewed → workout_start_clicked → workout_started →
   workout_first_exercise_started → workout_completed`. Sem % negativo; etapa com mais
   eventos que a anterior → marcar `incomplete`/`inconsistent`, não abandono enganoso.
4. **Retenção e Hábito** — coortes semanais D1/D3/D7/D14/D30, retorno vs valor (separados),
   "coorte ainda não madura" em vez de zero.
5. **Treinos e Produto** — criados/visualizados/iniciados/abandonados/concluídos, taxa,
   duração real, troca de exercício, quick vs complete. Sem dados de saúde identificáveis.
6. **Onboarding** — corrigir denominadores/duplicidades/abandono negativo; completion rate,
   tempo até treino, treino em 24h, retenção D7 por fluxo.
7. **Android e Push** — first opens, instalações, versão/build, permissão/tokens, funil
   scheduled→sent→delivered→opened, início/conclusão após push, falhas, treatment/control.
8. **Receita** — trial/paywall/checkout/assinatura/renovação/cancelamento, conversão por
   plataforma/fluxo, treinos antes da compra, tempo até compra.
9. **Experimentos** — base `experiment_assignments` (experiment_id, variant, assignment,
   exposure, conversão). Sem motor de A/B agora.
10. **Qualidade dos Dados** (admin técnico) — eventos recebidos/rejeitados/duplicados/
    sem user_id/sem session_id/platform unknown, atraso occurred_at→received_at, cobertura
    por evento; alertas: conclusão > início, % fora de 0–100, Android sem first_open,
    versão desconhecida crescendo.
11. **Usuários** — sem e-mail/nome (usar `EH-000123`), plataforma principal/última/versão,
    último acesso, treino criado/iniciado/concluído, instalação Android, push, coorte,
    experimento. Não rotular "baixo engajamento" sem definição documentada.

## Seção "Impacto do app Android" (análise central)

Coortes `Android first` / `Web only` / `PWA` / `Cross-platform` (por `activation_platform`).
Comparar treino criado→visualizado→iniciado→concluído, ativação 24h, 2º/3º treino em 7d,
retenção de valor D7/D30, frequência, assinatura.

**Linguagem obrigatória:** "associação observada", "diferença entre coortes", "amostra
insuficiente", "coorte ainda não madura". **Nota fixa:** _"Usuários que escolhem instalar
o app podem ser naturalmente mais engajados. A comparação observacional não elimina viés
de seleção."_ Não declarar causalidade sem experimento controlado.

## Banner de cobertura

"Dados disponíveis a partir de DD/MM/AAAA" para métricas `event_tracked`. Nunca exibir
zero quando o correto é "sem cobertura".
