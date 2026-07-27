-- bi_observability_daily
--
-- One row per day: check volume by status, plus incidents opened and resolved.
-- The "is the platform getting healthier or worse over time" view.
--
-- Storage is UTC; the day bucket is cut in America/Sao_Paulo so it lines up
-- with Analytics::ReportingTime and with every other daily figure in the admin
-- panel. A view cannot read ENV, so the zone is fixed here on purpose —
-- changing it requires a _v02.sql revision (see docs/observability/BI_VIEWS.md).
--
-- Columns are enumerated, never SELECT *: a later ALTER TABLE must not silently
-- change this view's shape, and pg_restore relies on the shape being stable.

CREATE OR REPLACE VIEW bi_observability_daily AS
WITH check_days AS (
  SELECT
    (checked_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
    environment                                                         AS environment,
    COUNT(*)                                                            AS total_checks,
    COUNT(*) FILTER (WHERE status = 'healthy')                          AS healthy_checks,
    COUNT(*) FILTER (WHERE status = 'warning')                          AS warning_checks,
    COUNT(*) FILTER (WHERE status = 'critical')                         AS critical_checks,
    COUNT(*) FILTER (WHERE status = 'insufficient_data')                AS insufficient_data_checks,
    COUNT(*) FILTER (WHERE status IN ('warning', 'critical')
                       AND check_key LIKE 'stale_heartbeat%')           AS jobs_failed,
    COUNT(*) FILTER (WHERE status IN ('warning', 'critical')
                       AND check_key IN ('make_delivery_backlog',
                                         'stripe_webhook_failure',
                                         'android_analytics_ingestion_stale')) AS integrations_failed
  FROM observability_check_results
  GROUP BY 1, 2
),
opened AS (
  SELECT
    (first_detected_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
    COUNT(*)                                        AS incidents_opened,
    COUNT(*) FILTER (WHERE severity = 'critical')   AS critical_incidents_opened
  FROM observability_incidents
  GROUP BY 1
),
resolved AS (
  SELECT
    (resolved_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS date,
    COUNT(*) AS incidents_resolved
  FROM observability_incidents
  WHERE resolved_at IS NOT NULL
  GROUP BY 1
),
all_days AS (
  SELECT date FROM check_days
  UNION
  SELECT date FROM opened
  UNION
  SELECT date FROM resolved
)
SELECT
  d.date                                       AS date,
  COALESCE(c.environment, 'production')        AS environment,
  COALESCE(c.total_checks, 0)                  AS total_checks,
  COALESCE(c.healthy_checks, 0)                AS healthy_checks,
  COALESCE(c.warning_checks, 0)                AS warning_checks,
  COALESCE(c.critical_checks, 0)               AS critical_checks,
  COALESCE(c.insufficient_data_checks, 0)      AS insufficient_data_checks,
  COALESCE(o.incidents_opened, 0)              AS incidents_opened,
  COALESCE(o.critical_incidents_opened, 0)     AS critical_incidents_opened,
  COALESCE(r.incidents_resolved, 0)            AS incidents_resolved,
  COALESCE(c.jobs_failed, 0)                   AS jobs_failed,
  COALESCE(c.integrations_failed, 0)           AS integrations_failed,
  -- NULL, not 0, when no check ran that day: "0% healthy" and "nothing was
  -- measured" are different facts and must not render the same.
  ROUND(COALESCE(c.healthy_checks, 0)::numeric / NULLIF(c.total_checks, 0), 4) AS healthy_rate
FROM all_days d
LEFT JOIN check_days c ON c.date = d.date
LEFT JOIN opened     o ON o.date = d.date
LEFT JOIN resolved   r ON r.date = d.date
ORDER BY d.date DESC;
