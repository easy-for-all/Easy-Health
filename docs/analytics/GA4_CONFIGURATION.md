# GA4 Configuration — EasyHealth

Property GA4: `G-FG3BDM75T1` · Google Ads: `AW-17759537883` (mesmo gtag, `layout.tsx`).
Property ID (Data API): `538436680` (ver `ga4-test/`).

## Key events (marcar no GA4)

`signup_completed`, `workout_created`, `workout_started`, `workout_completed`,
`checkout_completed`, `subscription_started`.

## Custom dimensions (event-scoped) — criar manualmente

`platform`, `app_surface`, `app_version`, `onboarding_flow`, `experiment_id`,
`experiment_variant`, `screen`.

## User properties (baixa cardinalidade) — criar manualmente

`platform_type`, `subscription_status`, `onboarding_flow`, `app_version`,
`activation_status`, `experiment_variant`.

**Não enviar**: `user_id` interno como propriedade legível, e-mail, nome, conteúdo de
saúde, textos livres, IDs de alta cardinalidade. `user_id` é setado via `gtag('set',{user_id})`
(reconciliação cross-device) — não como custom dimension legível.

## Consent Mode

Default `denied` (inline no `<head>`), `update` no opt-in. Validar em **DebugView**
que nenhum cookie de analytics é escrito antes do consentimento.

## Duplicação de page_view

`screen_view` é enviado manualmente. Para evitar dupla contagem com o Enhanced
Measurement, **desabilitar "Page views" do enhanced measurement** OU não tratar
`screen_view` como page_view. Documentar a escolha aqui após aplicar.

## Explorações / funis / coortes sugeridos

- Funil de ativação: `signup_completed → onboarding_started → workout_created →
  workout_viewed → workout_start_clicked → workout_started →
  workout_first_exercise_started → workout_completed`.
- Coortes de retenção por `platform`.
- Comparação Android vs Web por `platform`/`app_surface`.

## GA4 ≠ Admin

GA4 é exploratório e sujeito a consentimento/amostragem. **Contagem oficial de treinos,
receita e retenção vem do backend** (`product_analytics_events` + tabelas), nunca do GA4.

## Validação Android/Web

App Android = WebView do site → os eventos GA4 do Android são os mesmos do web (gtag no
browser interno), com `platform=android`. Não há SDK GA4 nativo (decisão de arquitetura).
