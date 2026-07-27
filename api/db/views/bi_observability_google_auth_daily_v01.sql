-- bi_observability_google_auth_daily
--
-- One row per day / flow / platform / build, with each failure reason as its
-- own column. Split by flow is not optional: native and web are separate code
-- paths, and a blended error rate hides a total native outage behind healthy
-- web traffic.
--
-- consent_required is broken out from the other failures on purpose. It is
-- EXPECTED when someone signs in to an account that does not exist yet, and is
-- only a defect when the client had already collected consent — which is why
-- consent_required_with_terms exists as a separate column. Do not add them
-- together.
--
-- error_rate is NULL when there were no attempts, never 0.

CREATE OR REPLACE VIEW bi_observability_google_auth_daily AS
SELECT
  (occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
  COALESCE(NULLIF(properties->>'auth_flow', ''), 'unknown')            AS flow,
  platform                                                             AS platform,
  COALESCE(NULLIF(app_version, ''), 'unknown')                         AS app_version,
  COALESCE(NULLIF(build_number, ''), 'unknown')                        AS app_build,

  COUNT(*)                                                             AS attempts,
  COUNT(*) FILTER (WHERE event_name = 'google_auth_succeeded')          AS successes,
  COUNT(*) FILTER (WHERE event_name = 'google_auth_failed')             AS failures,

  COUNT(*) FILTER (WHERE properties->>'error_code' = 'consent_required') AS consent_required,
  -- The anomalous subset: consent was collected AND the server still refused.
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'consent_required'
                     AND properties->>'auth_intent' = 'sign_up'
                     AND properties->>'terms_accepted' = 'true')        AS consent_required_with_terms,
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'invalid_token')    AS invalid_token,
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'invalid_audience') AS invalid_audience,
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'provider_error')   AS provider_error,
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'account_deleted')  AS account_deleted,
  COUNT(*) FILTER (WHERE properties->>'error_code' = 'internal_error')   AS internal_error,

  ROUND(
    COUNT(*) FILTER (WHERE event_name = 'google_auth_failed')::numeric
    / NULLIF(COUNT(*), 0),
    4
  )                                                                    AS error_rate
FROM product_analytics_events
WHERE event_name IN ('google_auth_succeeded', 'google_auth_failed')
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1 DESC, 2, 3;
