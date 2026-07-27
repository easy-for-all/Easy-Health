-- bi_observability_android_build_daily
--
-- One row per day per app version/build: installs, links, registrations and
-- Google auth outcomes. The table that answers "which build broke signup?".
--
-- Denominator is app_installations, deliberately: analytics events are
-- consent-gated and would undercount exactly the users this view exists to find.
--
-- Rates use NULLIF so an empty denominator yields NULL, never 0. A build with
-- two installs and no signups has an UNKNOWN conversion rate, not a 0% one.
--
-- Day bucket in America/Sao_Paulo — see bi_observability_daily_v01.sql.

CREATE OR REPLACE VIEW bi_observability_android_build_daily AS
WITH installs AS (
  SELECT
    (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
    COALESCE(NULLIF(app_version, ''), 'unknown')                        AS app_version,
    COALESCE(NULLIF(app_build, ''), 'unknown')                          AS app_build,
    CASE
      WHEN (CASE WHEN app_build ~ '^[0-9]{1,9}$' THEN app_build::int END) IS NULL THEN 'unknown'
      ELSE 'reported'
    END                                                                 AS build_group,
    COUNT(*)                                                            AS installations,
    COUNT(*) FILTER (WHERE first_authenticated_request_at IS NOT NULL)   AS authenticated_installations,
    COUNT(*) FILTER (WHERE user_id IS NOT NULL)                          AS linked_installations
  FROM app_installations
  WHERE platform = 'android'
  GROUP BY 1, 2, 3, 4
),
events AS (
  SELECT
    (occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
    COALESCE(NULLIF(app_version, ''), 'unknown')                         AS app_version,
    COALESCE(NULLIF(build_number, ''), 'unknown')                        AS app_build,
    COUNT(*) FILTER (WHERE event_name = 'android_registration_started')   AS registrations_started,
    COUNT(*) FILTER (WHERE event_name = 'android_registration_succeeded') AS registrations_succeeded,
    COUNT(*) FILTER (WHERE event_name = 'android_registration_failed')    AS registrations_failed,
    COUNT(*) FILTER (WHERE event_name IN ('google_auth_succeeded', 'google_auth_failed')) AS google_auth_attempts,
    COUNT(*) FILTER (WHERE event_name = 'google_auth_succeeded')          AS google_auth_succeeded,
    COUNT(*) FILTER (WHERE event_name = 'google_auth_failed')             AS google_auth_failed
  FROM product_analytics_events
  WHERE platform = 'android'
    AND event_name IN ('android_registration_started', 'android_registration_succeeded',
                       'android_registration_failed', 'google_auth_succeeded', 'google_auth_failed')
  GROUP BY 1, 2, 3
),
keys AS (
  SELECT date, app_version, app_build FROM installs
  UNION
  SELECT date, app_version, app_build FROM events
)
SELECT
  k.date                                      AS date,
  k.app_version                               AS app_version,
  k.app_build                                 AS app_build,
  COALESCE(i.build_group, 'unknown')          AS build_group,
  COALESCE(i.installations, 0)                AS installations,
  COALESCE(i.authenticated_installations, 0)  AS authenticated_installations,
  COALESCE(i.linked_installations, 0)         AS linked_installations,
  COALESCE(e.registrations_started, 0)        AS registrations_started,
  COALESCE(e.registrations_succeeded, 0)      AS registrations_succeeded,
  COALESCE(e.registrations_failed, 0)         AS registrations_failed,
  COALESCE(e.google_auth_attempts, 0)         AS google_auth_attempts,
  COALESCE(e.google_auth_succeeded, 0)        AS google_auth_succeeded,
  COALESCE(e.google_auth_failed, 0)           AS google_auth_failed,
  ROUND(i.linked_installations::numeric / NULLIF(i.installations, 0), 4) AS registration_conversion_rate,
  ROUND(i.linked_installations::numeric / NULLIF(i.installations, 0), 4) AS linkage_rate,
  ROUND(e.google_auth_failed::numeric / NULLIF(e.google_auth_attempts, 0), 4) AS google_auth_error_rate
FROM keys k
LEFT JOIN installs i
  ON i.date = k.date AND i.app_version = k.app_version AND i.app_build = k.app_build
LEFT JOIN events e
  ON e.date = k.date AND e.app_version = k.app_version AND e.app_build = k.app_build
ORDER BY k.date DESC, k.app_build DESC;
