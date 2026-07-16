# Privacy & Data Handling — EasyHealth (LGPD)

## Princípios

- **Consent Mode v2 (LGPD)**: GA4/Ads/Clarity iniciam com `analytics_storage`/`ad_storage`
  = `denied` (default inline em `layout.tsx`), só `granted` após opt-in
  (`analytics/consent.ts` → `updateConsent`). Escolha persistida em `localStorage: eh_consent`.
- **Sem localização precisa**: nunca pedir GPS para analytics. Análises geográficas só
  com país/região/cidade agregada de ferramentas (GA4). IP bruto não é persistido.
- **Limiar mínimo**: não exibir segmento geográfico com < 5 usuários (`ANALYTICS_MIN_SAMPLE`).
- **Sem identificadores invasivos**: não armazenar advertising ID, IMEI ou Android ID.
  A instalação é identificada por `anonymous_id` (UUID próprio) e, no futuro,
  `app_installations.installation_uuid`.

## Dados NUNCA coletados em `properties`

senha, token, texto de exames, fotos, conteúdo médico, nome completo, e-mail,
telefone, endereço, GPS, dados sensíveis livres, resposta completa de IA.
Sanitização automática no backend (`SENSITIVE_KEY_PATTERN`) e rejeição/log via
`analytics_event_rejected` (sem payload sensível).

## Identidade

- `anonymous_id` — UUID em `localStorage`, sobrevive a logout. Associado ao `user_id`
  no servidor na ingestão (nunca confiando no `user_id` do cliente).
- `user_id` interno **não** é enviado como propriedade legível ao GA4 (só via `set user_id`).

## Máscara no Clarity (a garantir na config)

formulários, nome, e-mail, dados físicos, limitações, exames, fotos, respostas de IA.
Ver `GA4_CONFIGURATION.md` e a config do Clarity.

## Política de retenção

- `product_analytics_events` — eventos brutos recentes para análise. Política de
  expurgo futura (ex.: manter bruto 180d, agregações preservadas). **Nenhuma exclusão
  destrutiva é executada agora.**

## Texto legal a revisar

Como esta entrega passa a coletar `anonymous_id`/`session_id`, plataforma, versão do
app e eventos de produto próprios (além do GA4), a Política de Privacidade
(`web/src/app/privacy/page.tsx`) deve ser revisada para descrever: coleta de eventos
de uso próprios, base legal, retenção e Consent Mode. **Não alterar o documento legal
silenciosamente** — listar as mudanças para revisão jurídica.
