# Metric Definitions — EasyHealth

Toda métrica do Admin retorna um `Analytics::MetricResult`:

```json
{ "value": 5.8, "numerator": 21, "denominator": 360, "sample_size": 360,
  "status": "complete", "cohort_maturity": "mature", "definition": "first_workout_conversion_v1" }
```

`status` ∈ `complete` · `incomplete` · `insufficient_sample` (< `ANALYTICS_MIN_SAMPLE`, default 5)
· `inconsistent` (numerador > denominador) · `no_coverage` (denominador 0).
Percentual sempre clampado a **[0,100]** — nunca negativo, nunca > 100%.

**Base de todos os denominadores:** `User.reportable` (exclui `test_account`,
anonimizados, `deletion_requested_at` e domínios internos de `ANALYTICS_INTERNAL_EMAIL_DOMAINS`).

**Timezone:** cortes diários e janelas via `Analytics::ReportingTime`
(`ANALYTICS_REPORTING_TIMEZONE`, default `America/Sao_Paulo`), com `AT TIME ZONE`.

## North Star — Weekly Active Trainees

Usuários `reportable` únicos com ≥ 1 **treino concluído válido** (`completion_status="completed"`)
nos últimos 7 dias (janela em timezone de reporte).

## Métricas principais

1. **Activation 24h** (`activation_24h_v1`) — usuários que concluíram o 1º treino
   ≤ 24h de `signup_completed` ÷ elegíveis que concluíram cadastro. Apresentar também:
   iniciou em 24h, concluiu em 24h, mediana até início, mediana até conclusão.
2. **First Workout Conversion** (`first_workout_conversion_v1`) — usuários com
   `workout_completed` ÷ usuários com `workout_created`.
3. **Habit Formation 7d** (`habit_7d_v1`) — usuários com ≥ 2 treinos concluídos nos
   primeiros 7 dias (também corte de 3).
4. **Retenção** — coortes por data de cadastro. Duas visões que **não se misturam**:
   - **Retorno** (`retention_return_dN`): abriu o produto de novo.
   - **Valor** (`retention_value_dN`): concluiu novo treino. _Implementado: D1/D7/D30
     em `admin_controller` (`retention_detail`), timezone-aware, base reportable._
   Coorte sem N dias de observação → **não entra no denominador** (cohort_maturity),
   exibir "coorte ainda não madura", nunca zero.
5. **Frequência** — treinos concluídos por usuário ativo; mediana; distribuição
   0/1/2/3/4+; intervalo médio entre treinos.
6. **Android vs Web** — coortes `cohort_platform` (= `users.activation_platform`,
   plataforma do 1º evento; **não** reclassificar pela última sessão). Comparar todo
   o funil + ativação/hábito/retenção/frequência/assinatura. Ver `ADMIN_DASHBOARD.md`
   (nota de viés de seleção obrigatória).
7. **Qualidade operacional Android** — first opens, instalações ativas, versão/build,
   push permission, tokens ativos, deep link success, login success, crashes (Sentry).

## Cobertura & proveniência

- `event_tracked` — vindo de `product_analytics_events` (a partir do deploy).
- `historical_derived` — reconstruído de tabelas existentes (planos/sessões).
- `incomplete` — instrumentação parcial; nunca calcular abandono enganoso.

O Admin exibe "Dados disponíveis a partir de DD/MM/AAAA" para métricas `event_tracked`.
