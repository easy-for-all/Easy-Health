# Firebase — Manual Setup Checklist

Usa o **mesmo** projeto Firebase de produção e o `google-services.json` já injetado
pelo CI (secret `GOOGLE_SERVICES_JSON_BASE64`). **Não** criar segundo projeto, **não**
criar service account nova para Analytics/Crashlytics/Performance/FCM.

## 1. Automático pelo código (feito nesta entrega)
| Item | Onde |
|---|---|
| SDKs Analytics/Crashlytics/Performance | `@capacitor-firebase/*@8.3.0` (`web/package.json`) |
| Plugins Gradle Crashlytics/Perf | `web/android-config/build.gradle` + `app-build.gradle` (guard google-services) |
| Deploy do `build.gradle` raiz no CI | `.github/workflows/android-internal-testing.yml` |
| Camada JS única | `web/src/shared/lib/analytics/firebase.ts` |
| Roteamento anti-duplicidade | `web/src/shared/lib/analytics/index.ts` |

## 2. Automático via CLI segura (opcional)
| Item | Comando |
|---|---|
| Inspecionar apps do projeto | `firebase apps:list` (já autenticado) |
| Conferir SHA (App Links/Google Sign-In) | Console → Project settings → SHA certificate fingerprints |

## 3. Obrigatório no Firebase Console (manual)
- [ ] Confirmar o app Android `com.EasyHealth.myapp` no projeto.
- [ ] Google Analytics **habilitado** no projeto e propriedade GA4 vinculada.
- [ ] SHA-1/SHA-256 do App Signing (Play) cadastrados (login social).
- [ ] Crashlytics: aceitar/abrir o dashboard (primeiro crash "arma" o produto).
- [ ] Performance: confirmar recebimento de traces.
- [ ] Cloud Messaging: já em uso (não alterar).
- [ ] Validar DebugView com o aparelho de teste.

## 4. Obrigatório no GA4 (manual)
- [ ] Conferir o data stream **Android** (separado do Web `G-FG3BDM75T1`).
- [ ] Conferir chegada dos eventos.
- [ ] Marcar conversões recomendadas (ver `docs/analytics/GA4_CONFIGURATION.md` e Fase 29): `user_registered`/`signup_completed`, `onboarding_completed`, `workout_created`, `workout_started`, `workout_completed`, `checkout_started`, `subscription_started`.
- [ ] Dimensões customizadas só quando necessárias: `platform`, `app_version`, `onboarding_flow`, `subscription_status`, `campaign`. Evitar duplicar com o Web.

## 5. Obrigatório no Google Play Console (manual)
- [ ] Package `com.EasyHealth.myapp` e App Signing conferidos.
- [ ] Integração com Firebase (Android Vitals) ativa.
- [ ] Release interno validado.

## 6. Google Ads (se usado)
- [ ] Vincular GA4/Firebase; importar conversões; validar Install Referrer.

## 7. Credenciais
- Analytics/Crashlytics/Performance/FCM: **não exigem** credencial nova — usam o
  `google-services.json` (config Android, **não** service account).
- GA4 Data API (futuro, se reconciliação): backend + conta de **leitura** + cache;
  **não** pedir Owner/Editor/Firebase Admin; **não** reutilizar a service account do Play.
