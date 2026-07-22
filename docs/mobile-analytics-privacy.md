# Mobile Analytics — Privacidade e LGPD

Complementa `docs/analytics/PRIVACY_AND_DATA_HANDLING.md` para a camada mobile/Android.

## Ferramentas, dados e finalidade
| Ferramenta | Dados | Finalidade | PII? |
|---|---|---|---|
| Backend próprio (`product_analytics_events`, `app_installations`) | eventos de produto, contexto de dispositivo não-PII, installation_id pseudônimo | fonte de verdade de funil/instalações | Não (allowlist) |
| Firebase Analytics (nativo) | eventos comportamentais, user properties permitidas | análise Android | Não |
| Firebase Crashlytics | stacktrace nativo, id pseudônimo | estabilidade | Não |
| Firebase Performance | traces de baixa cardinalidade | desempenho | Não |
| GA4 Web (WebView) | eventos web/PWA | análise web | Não (Consent Mode) |
| Sentry | erros JS/Rails, email mascarado | diagnóstico | Mascarado |
| Make | eventos de relacionamento (email/nome quando elegível) | CRM/marketing | Sim (consentido) |

## Minimização — allowlist por código
- **Propriedades proibidas** (bloqueadas em `firebase.ts` `FORBIDDEN_PROPERTY_KEYS` e
  sanitizadas no backend `RelationshipEventTracker.sanitize_metadata`): `email`, `name`,
  `phone`, `cpf`, `medical_data`, `injury`, `limitation_text`, `coach_message`,
  `access_token`, `refresh_token`, `fcm_token`.
- **User properties Firebase permitidas** (`ALLOWED_USER_PROPERTIES`): `subscription_status`,
  `onboarding_flow`, `experience_level`, `app_language`, `app_version_group`.
- **installation_id**: UUID aleatório pseudônimo; **nunca** vira Firebase user id (o
  Firebase user id é o id interno pseudônimo, nunca email).
- Nunca enviar Advertising ID (as 5 permissões AD_ID/AdServices são removidas no Manifest).

## Consentimento
- GA4/Ads: Google Consent Mode v2, default `denied` até opt-in (`consent.ts`).
- Firebase Analytics: coleta espelha o consentimento (`setFirebaseAnalyticsConsent`).
- **Validação jurídica necessária**: definir na política se a coleta de telemetria
  técnica e eventos de produto (backend/Firebase) exige consentimento explícito prévio
  ou se se enquadra em legítimo interesse/execução de contrato. Este documento não
  substitui parecer jurídico.

## Logout e exclusão de conta
- **Logout**: remove o Firebase user id e o `user_id` do GA4; **preserva** o
  `installation_id` (mesma instalação, contexto anônimo).
- **Exclusão de conta**: dissociar/excluir conforme política; `app_installations.user_id`
  fica nulo (instalação preservada anonimamente) ou removido conforme retenção.

## Retenção
- `product_analytics_events`: aplicar política de retenção/sampling para eventos técnicos
  de alto volume (ver `TELEMETRY_SAMPLE_RATE`, Fase K).
- Firebase/GA4: retenção configurada no Console (padrão da propriedade).
