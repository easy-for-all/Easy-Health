# Experimento Android — conta após o onboarding

`android_post_onboarding_gate_v1`

Compara duas experiências no fim do onboarding pré-auth do Android nativo:

| Variante | Fim do onboarding |
|---|---|
| `account_gate` | resumo → `/sign-up` → conta → plano (fluxo atual) |
| `open_app` | resumo → abre o app e gera o plano sem conta (modo anônimo) |

Web e PWA não participam. Usuário autenticado não participa.

## Como ligar

Três variáveis no frontend (inlined no build — exigem **rebuild**, não basta
reiniciar o container) e duas no backend (lidas em tempo de chamada):

```bash
# web/.env — comportamento
NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_ENABLED=true
NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_MIN_BUILD=<build publicado com o A/B>
NEXT_PUBLIC_ANDROID_POST_ONBOARDING_AB_STARTED_AT=<timestamp ISO do deploy>

# api/.env — corte de ANÁLISE do painel
ANDROID_POST_ONBOARDING_AB_MIN_BUILD=<mesmo build>
ANDROID_POST_ONBOARDING_AB_STARTED_AT=<mesmo timestamp>

# api/.env — o modo anônimo, do qual open_app depende
ANONYMOUS_GENERATION_ENABLED=true
ANONYMOUS_MODE_MIN_BUILD=<mesmo build>
ANONYMOUS_GENERATION_DAILY_GLOBAL_MAX=500
```

As duas famílias precisam ficar **em sincronia**. O bundle do cliente não lê env
de servidor, e se os cortes divergirem o painel mede uma população enquanto o
app trata outra.

**Ligar `NEXT_PUBLIC_..._ENABLED` antes de `ANONYMOUS_GENERATION_ENABLED` manda
metade dos usuários para um fluxo que o backend recusa.** A ordem é: modo
anônimo primeiro, experimento depois.

## Validação em produção, depois do deploy

### 1. Distribuição por variante

O denominador de tudo. Deve ficar perto de 50/50 e crescer com o tráfego.

```sql
SELECT properties->>'variant' AS variant,
       COUNT(DISTINCT properties->>'installation_id') AS installations
FROM product_analytics_events
WHERE event_name = 'experiment_exposed'
  AND properties->>'experiment_key' = 'android_post_onboarding_gate_v1'
GROUP BY 1
ORDER BY 1;
```

### 2. Eventos sem installation_id

**Se isto não for zero, nenhum outro número descreve uma população
reconstruível.** É o primeiro a checar, sempre.

```sql
SELECT event_name, COUNT(*) AS events
FROM product_analytics_events
WHERE event_name IN ('experiment_assigned', 'experiment_exposed')
  AND properties->>'experiment_key' = 'android_post_onboarding_gate_v1'
  AND properties->>'installation_id' IS NULL
GROUP BY 1;
```

Esperado: **0 linhas**.

### 3. Instalação com mais de uma variante

Split-brain. O índice único parcial em `analytics_experiment_assignments`
impede no banco; esta consulta verifica se aconteceu na trilha de eventos.

```sql
SELECT properties->>'installation_id' AS installation_id,
       COUNT(DISTINCT properties->>'variant') AS variants
FROM product_analytics_events
WHERE event_name = 'experiment_exposed'
  AND properties->>'experiment_key' = 'android_post_onboarding_gate_v1'
GROUP BY 1
HAVING COUNT(DISTINCT properties->>'variant') > 1;
```

Esperado: **0 linhas**.

### 4. Tabela de atribuição versus eventos observados

`stored` é o que o backend gravou, `observed` é o que o cliente emitiu. Só a
diagonal deve ter volume.

```sql
SELECT a.variant AS stored,
       e.properties->>'variant' AS observed,
       COUNT(DISTINCT a.installation_id) AS installations
FROM analytics_experiment_assignments a
JOIN product_analytics_events e
  ON e.properties->>'installation_id' = a.installation_id
 AND e.event_name = 'experiment_exposed'
WHERE a.experiment_key = 'android_post_onboarding_gate_v1'
GROUP BY 1, 2
ORDER BY 1, 2;
```

### 5. Conversão em 24h a partir do `exposed_at` de CADA instalação

A janela é relativa à exposição daquela instalação, nunca a um corte global do
período: quem foi exposto às 23h e quem foi às 8h teriam janelas de duração
diferente sob um corte único.

```sql
WITH exposure AS (
  SELECT properties->>'installation_id' AS installation_id,
         MIN(properties->>'variant')    AS variant,
         MIN(occurred_at)               AS exposed_at
  FROM product_analytics_events
  WHERE event_name = 'experiment_exposed'
    AND properties->>'experiment_key' = 'android_post_onboarding_gate_v1'
  GROUP BY 1
)
SELECT x.variant,
       COUNT(*) AS exposed,
       COUNT(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM product_analytics_events e
         WHERE e.properties->>'installation_id' = x.installation_id
           AND e.event_name IN ('workout_first_exercise_started', 'workout_started')
           AND e.occurred_at BETWEEN x.exposed_at AND x.exposed_at + interval '24 hours'
       )) AS started_24h
FROM exposure x
GROUP BY 1
ORDER BY 1;
```

### 6. Jornada por instalação (investigação de caso)

```sql
WITH exposure AS (
  SELECT properties->>'installation_id' AS installation_id,
         MIN(properties->>'variant')    AS variant,
         MIN(occurred_at)               AS exposed_at
  FROM product_analytics_events
  WHERE event_name = 'experiment_exposed'
    AND properties->>'experiment_key' = 'android_post_onboarding_gate_v1'
  GROUP BY 1
)
SELECT x.installation_id,
       x.variant,
       x.exposed_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'onboarding_completed')   AS onboarding_completed_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'auth_screen_viewed')     AS account_gate_viewed_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'auth_provider_clicked')  AS auth_clicked_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'signup_completed')       AS account_created_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'workout_created')        AS plan_generated_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'workout_viewed')         AS workout_viewed_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'workout_first_exercise_started') AS first_exercise_started_at,
       MIN(e.occurred_at) FILTER (WHERE e.event_name = 'workout_completed')      AS workout_completed_at
FROM exposure x
LEFT JOIN product_analytics_events e
  ON e.properties->>'installation_id' = x.installation_id
 AND e.occurred_at >= x.exposed_at
GROUP BY 1, 2, 3
ORDER BY x.exposed_at DESC
LIMIT 50;
```

### 7. Saúde do modo anônimo

Erros de geração e conflitos de vínculo vêm do **servidor**, não de eventos do
cliente: o cliente não enxerga uma falha que aconteceu no backend, então um
funil só de eventos reportaria zero erro justamente quando a geração quebrou.

```sql
SELECT last_generation_status,
       COUNT(*) AS sessions,
       COUNT(*) FILTER (WHERE plans_generated_count >= 3) AS at_limit,
       COUNT(*) FILTER (WHERE claimed_at IS NOT NULL)     AS claimed
FROM anonymous_onboarding_sessions
GROUP BY 1
ORDER BY 1;

SELECT last_claim_failure_code, COUNT(*) AS sessions
FROM anonymous_onboarding_sessions
WHERE last_claim_failure_code IS NOT NULL
GROUP BY 1;
```

## Como ler o painel

Admin → seção "Experimento Android — conta após o onboarding", logo abaixo do
funil Android.

- **A unidade é uma instalação exposta.** Atribuídas incluem quem nunca chegou
  ao fim do onboarding; dividir por elas mediria abandono do wizard.
- **`—` não é `0%`.** Um traço significa "não houve ninguém para converter";
  um zero afirmaria que ninguém converteu.
- **O painel não declara vencedor.** Ele mostra tamanho de amostra, taxa por
  variante, diferença absoluta em pontos percentuais e relativa. Decidir exige
  horizonte definido antes do início e métrica primária pré-registrada.

| Expostas por variante | Leitura |
|---|---|
| < 30 | amostra muito baixa — resultado apenas direcional |
| 30–99 | amostra baixa — não concluir ainda |
| ≥ 100 | leitura mais estável, ainda observacional |

## Confounder conhecido

O plano anônimo pula `FitnessIntelligence` / `WorkoutStrategy`, porque as duas
derivam do `fitness_profile` da conta, que não existe antes dela. O plano passa
pela **mesma IA** nos dois braços — rebaixá-lo faria o experimento medir
qualidade de treino em vez de momento do cadastro —, mas a camada de estratégia
fica de fora em `open_app`. Um usuário recém-cadastrado recebe o mesmo
tratamento na primeira geração, então a diferença é menor do que parece; ainda
assim, não é zero.
