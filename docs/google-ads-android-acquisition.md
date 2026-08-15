# Aquisição Android — Google Ads × EasyHealth

Painel Admin em `/admin/android-acquisition`. Coloca lado a lado o que o **Google Ads
atribuiu** à campanha Android e o que o **produto realmente registrou**, sem misturar os dois.

---

## Por que dois blocos separados

| | Google Ads | EasyHealth |
|---|---|---|
| O que é | atribuição publicitária do Google | comportamento registrado no nosso banco |
| Data | `segments.date` (regras de reporting do Google) | data de criação da conta, em America/Sao_Paulo |
| Unidade | conversões atribuídas (podem ser **decimais**) | contas (inteiros) |
| Origem | cache `google_ads_daily_metrics` | `users` / `workout_plans` / `workout_sessions` |

Os volumes **não precisam bater**. Uma diferença entre os blocos não é, por si só, erro,
perda ou tracking quebrado — são universos de medição diferentes.

**Não existe taxa cruzando os dois blocos.** Dividir instalações atribuídas por contas
EasyHealth seria uma atribuição por usuário que esta versão deliberadamente não faz
(sem gclid, sem install referrer, sem Firebase instance id → user).

---

## Arquitetura

```
cron (1x/hora)
  └─ rake google_ads:sync_android_acquisition
       └─ GoogleAdsAndroidAcquisitionSyncJob   (heartbeat google_ads_acquisition_sync)
            └─ GoogleAds::AndroidAcquisitionSync
                 └─ GoogleAds::Client  → API do Google Ads (REST, v25)
                      ⇩
                 google_ads_daily_metrics   (cache; upsert idempotente)

Admin abre a página
  └─ GET /api/v1/admin/analytics/android_acquisition
       └─ Analytics::AndroidAcquisition
            ├─ lê google_ads_daily_metrics   ← NUNCA chama o Google
            └─ lê users / workout_plans / workout_sessions
```

| Arquivo | Papel |
|---|---|
| `api/app/services/google_ads/client.rb` | transporte REST, OAuth, paginação, retry |
| `api/app/services/google_ads/android_acquisition_sync.rb` | as duas queries GAQL + upsert |
| `api/app/services/google_ads/discovery.rb` | listagem de campanhas e conversion actions |
| `api/app/services/analytics/android_acquisition.rb` | payload do painel (Ads + produto) |
| `api/app/models/google_ads_daily_metric.rb` | cache diário por (data, campanha) |
| `api/app/jobs/google_ads_android_acquisition_sync_job.rb` | job idempotente com heartbeat |
| `api/lib/tasks/google_ads.rake` | `sync_android_acquisition` e `discover` |
| `web/src/app/(app)/admin/android-acquisition/` | página e helpers do painel |

Cliente: **REST oficial da API do Google Ads**, autenticado com `googleauth`/`signet`
(já usados pelo `FirebasePushService`). A gem `google-ads-googleads` não foi adicionada
porque arrasta `grpc` + `protobuf` (compilação nativa na imagem Docker) para duas
consultas de leitura por hora. Nada aqui usa scraping da UI.

**Versão da API**: `GoogleAds::Client::API_VERSION = "v25"`, num único ponto do código.
Não é ENV de propósito: subir de major version muda o conjunto de campos GAQL válidos e
precisa passar por código + testes, não por um flip em produção.

---

## ENVs

Todas no `.env` da raiz (o `docker-compose` passa o arquivo inteiro para o container `api`).
Nenhuma vai para o frontend, HTML, resposta de API, log ou Git.

| ENV | Obrigatória | Observação |
|---|---|---|
| `GOOGLE_ADS_DEVELOPER_TOKEN` | sim | API Center da conta MCC |
| `GOOGLE_ADS_CLIENT_ID` | sim | cliente OAuth próprio |
| `GOOGLE_ADS_CLIENT_SECRET` | sim | |
| `GOOGLE_ADS_REFRESH_TOKEN` | sim | escopo `https://www.googleapis.com/auth/adwords` |
| `GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH` | sim | com ou sem hífen; a API recebe só dígitos |
| `GOOGLE_ADS_LOGIN_CUSTOMER_ID` | não | só quando a conta é gerenciada por MCC |
| `GOOGLE_ADS_ANDROID_CAMPAIGN_ID` | sim | campanha Android **atual** |
| `GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID` | sim | conversão de instalação |
| `GOOGLE_ADS_SIGNUP_CONVERSION_ACTION_ID` | sim | conversão `sign_up` |

Esta é uma credencial **backend → Google Ads**. Não tem relação com o Google Sign-In dos
usuários EasyHealth (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`), que não foi tocado.

Faltando qualquer obrigatória, o painel continua abrindo com
`sync.status = "not_configured"` e o bloco EasyHealth preenchido normalmente.

### Como obter o refresh token

1. Crie um **OAuth client** do tipo Desktop no mesmo projeto Google Cloud da conta de Ads.
2. Autorize uma conta que tenha acesso à conta de anúncios, pedindo o escopo
   `https://www.googleapis.com/auth/adwords` e `access_type=offline`.
3. Guarde o `refresh_token` retornado no `.env` do servidor. Ele não expira com o uso normal.

---

## Descobrindo os IDs

```bash
docker compose -f docker-compose.prod.yml exec api bin/rails google_ads:discover
```

Lista campanhas (ID, nome, status, `advertising_channel_type`, `advertising_channel_sub_type`,
`app_id`, `app_store`) e conversion actions (ID, nome, status, `type`, `category`, `origin`,
`primary_for_goal`).

Campanhas de app / do pacote `com.EasyHealth.myapp` aparecem marcadas com `*` e primeiro,
apenas para facilitar a leitura. **Nada é escolhido automaticamente**: nome de campanha e
de conversão são rótulos editáveis no painel do Google, e selecionar por texto faria um KPI
mudar de significado sozinho. Existe mais de uma campanha Android no histórico — confira
qual é a atual antes de preencher `GOOGLE_ADS_ANDROID_CAMPAIGN_ID`. A campanha anterior não
é somada nem apagada; esta versão observa **uma** campanha configurada.

---

## Sincronização

```bash
# janela padrão: hoje + os 7 dias anteriores (8 datas, hoje incluído)
docker compose -f docker-compose.prod.yml exec api bin/rails google_ads:sync_android_acquisition

# janela maior, pontual
docker compose -f docker-compose.prod.yml exec api env DAYS=30 bin/rails google_ads:sync_android_acquisition
```

A janela móvel existe porque o Google **revisa retroativamente** as conversões atribuídas de
dias já reportados. Re-sincronizar os últimos 8 dias a cada hora deixa o cache autocorretivo
sem nenhuma máquina de backfill.

### Cron

O diretório de produção é `/home/easy/Easy-Health` (veja `.github/workflows/deploy.yml`).
Entrada sugerida — **não instalada por esta tarefa**:

```cron
5 * * * * cd /home/easy/Easy-Health && docker compose -f docker-compose.prod.yml exec -T api bin/rails google_ads:sync_android_acquisition >> /var/log/easyhealth-google-ads.log 2>&1
```

O job registra o heartbeat `google_ads_acquisition_sync` (intervalo esperado: 1h), então um
cron que parar de rodar aparece no painel de observabilidade em vez de congelar os números
em silêncio.

---

## As duas queries

**Query A — performance** (única fonte de custo):

```sql
SELECT campaign.id, campaign.name, segments.date,
       metrics.impressions, metrics.clicks, metrics.cost_micros
FROM campaign
WHERE campaign.id = <CAMPAIGN_ID>
  AND segments.date BETWEEN <START> AND <END>
```

**Query B — conversões por ação** (sem nenhuma coluna de custo):

```sql
SELECT campaign.id, campaign.name, segments.date,
       segments.conversion_action, segments.conversion_action_name,
       metrics.conversions, metrics.all_conversions
FROM campaign
WHERE campaign.id = <CAMPAIGN_ID>
  AND segments.date BETWEEN <START> AND <END>
```

Segmentar por `conversion_action` multiplica cada linha do dia pela quantidade de ações que
converteram. Se o custo viesse dessa query, uma campanha com três ações reportaria **três
vezes o gasto**. Por isso são duas consultas independentes, e a Query B não seleciona custo
— o erro fica impossível, não apenas improvável.

Não existe métrica "installs" na API: a instalação da App Campaign **é** uma conversion
action, identificada pelo ID configurado (comparado pelo número no fim do resource name,
para que renomear a conversão no painel não quebre nada). Qualquer outra conversion action
da campanha é ignorada nesses dois KPIs.

`metrics.conversions` é o que a UI do Google Ads chama de **Conversions** e é o que o painel
mostra. `metrics.all_conversions` é lido só como diagnóstico: a rake imprime a diferença
entre as duas colunas. Divergência é informação sobre a configuração da conta — nunca motivo
para trocar de coluna silenciosamente.

---

## Definição de cada métrica

### Bloco Google Ads

| Métrica | Definição |
|---|---|
| Gasto | `metrics.cost_micros / 1_000_000`, só da Query A |
| Instalações atribuídas | `metrics.conversions` da conversion action de instalação |
| CPI | gasto ÷ instalações atribuídas — **`—` quando não há instalações**, nunca R$ 0,00 |
| Cadastros atribuídos | `metrics.conversions` da conversion action `sign_up` |
| CPA cadastro | gasto ÷ cadastros atribuídos — `—` sem denominador |
| Instalação → cadastro | cadastros ÷ instalações, **dentro do Google Ads** |
| Impressões / Cliques | Query A |

Conversões atribuídas são **decimais** (atribuição data-driven / cross-device). O painel
mostra inteiro quando o número é inteiro e duas casas quando há fração; nada é truncado.

Zero cadastros atribuídos num dia com gasto é um **zero legítimo** — campanha e conversão
são novas. O painel distingue isso de "não configurado" e de "sync falhou".

### Bloco EasyHealth

Coorte por **data de criação da conta** (America/Sao_Paulo): a linha do dia D conta as contas
Android criadas em D e, dessas **mesmas** contas, quantas depois avançaram. Não são eventos
soltos por dia — é isso que torna as taxas legítimas.

| Métrica | Fonte |
|---|---|
| Contas Android | `users.signup_source = 'android'`, filtradas por `Analytics::AccountClassification.exclude_non_external` |
| Criaram treino | existe `workout_plans` do usuário |
| Iniciaram treino | existe `workout_sessions` do usuário — a linha é criada no momento em que o treino começa |
| Concluíram treino | existe `workout_sessions` com `completion_status = 'completed'` |

`exclude_non_external` remove contas internas e do Google Play pre-launch report
(`@cloudtestlabaccounts.com`), que percorre o cadastro inteiro num aparelho real.

Coortes com menos de 1 dia vêm marcadas como `immature`: quem se cadastrou hoje ainda pode
treinar amanhã, e mostrar isso como taxa final de conversão seria mentira.

O rodapé reporta `completed_without_started`: contas que concluíram treino sem nenhuma sessão
registrada. Como concluir exige uma sessão, o valor é sempre `0` — o aviso existe só como
sentinela e nunca aparece no painel.

---

## Status da sincronização

Reaproveita a infraestrutura existente (`Observability::Heartbeat` + `MAX(synced_at)` do
cache). Nenhuma tabela nova de status foi criada.

| status | quando | rótulo |
|---|---|---|
| `ok` | cache com menos de 2h | Dados Google Ads atualizados |
| `stale` | cache com mais de 2h, **sem evidência de erro** | Dados Google Ads desatualizados |
| `error` | heartbeat com falha mais recente que o último sucesso | Última sincronização Google Ads falhou |
| `never_synced` | cache vazio | Google Ads ainda não sincronizado |
| `not_configured` | falta credencial ou campanha | Google Ads não configurado |

Dado apenas velho reporta **desatualizado**, nunca "indisponível": afirmar falha sem prova
de falha é ruído que faz o painel perder credibilidade.

---

## Comportamento em erro

- **Google fora do ar**: o endpoint responde **200** com o cache anterior intacto e
  `sync.status` em `error`/`stale`. Nada é apagado nem zerado.
- **Sem credenciais**: **200**, `sync.status = "not_configured"`, bloco EasyHealth normal.
- **503** só quando o próprio painel não consegue ser montado (erro de banco, exceção
  inesperada do agregador interno). Indisponibilidade do Google **não** derruba a página.
- **422** para intervalo personalizado inválido (formato, invertido, acima de 180 dias).

Retry no client: apenas `429/500/502/503/504`, no máximo 2 tentativas com backoff curto.
`400/401/403` são falha de configuração ou autenticação e sobem na hora — repetir só
atrasaria a linha de log que alguém precisa ler.

Todo erro registra o header `request-id` do Google (`GoogleAds API error status=… request_id=…`),
que é o que o suporte do Google pede. Developer token, access token, refresh token, client
secret e o header `Authorization` **nunca** aparecem em log.

---

## Validação contra a UI do Google Ads

Responder HTTP 200 não é validação. Antes de considerar o sync correto:

1. Escolha um período fechado (preferencialmente **ontem** ou os últimos 7 dias).
2. Compare, campanha a campanha: **custo, impressões, cliques, instalações, sign_up**.
3. Aceite diferença só com explicação documentada — latência de atribuição, janela de
   atribuição, diferença de fuso/data de reporting, conversões fracionárias.

Anote o resultado da comparação junto com o período usado.

---

## Troubleshooting

| Sintoma | Causa provável |
|---|---|
| `Google Ads não configurado` | falta ENV; a lista exata vem em `sync.missing_configuration` |
| `status=401` no log | refresh token revogado, ou gerado sem o escopo `adwords` |
| `status=403` no log | developer token sem acesso, ou falta `GOOGLE_ADS_LOGIN_CUSTOMER_ID` numa conta sob MCC |
| `status=400` no log | campo GAQL inválido para a v25 — confira a query contra a versão |
| Instalações sempre 0 | `GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID` apontando para outra ação; rode `google_ads:discover` |
| Custo parece multiplicado | sinal de que o custo passou a vir da query segmentada; ele só pode vir da Query A |
| Painel abre mas Ads vazio | `GOOGLE_ADS_ANDROID_CAMPAIGN_ID` de outra campanha |
| `Dados Google Ads desatualizados` | cron parado; confira `crontab -l` na VPS e o heartbeat `google_ads_acquisition_sync` |

---

## Fora de escopo desta versão

Atribuição por usuário (gclid, Google Install Referrer, Firebase instance id → user),
BigQuery, Looker Studio, GA4 Data API, gráficos, alertas automáticos, e qualquer escrita no
Google Ads (editar campanha, pausar, mexer em orçamento ou lance). O objetivo é
observabilidade simples.
