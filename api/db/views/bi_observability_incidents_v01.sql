-- bi_observability_incidents
--
-- One row per incident, with duration. Feeds MTTR, "which check cries wolf
-- most" and before/after-deploy comparisons.
--
-- duration_minutes uses NOW() for incidents that are still open, so an ongoing
-- incident reports how long it has been running rather than NULL.
--
-- dimensions is exposed as jsonb. It only ever contains the allow-listed,
-- low-cardinality keys from Observability::Fingerprint (build_group, auth_flow,
-- heartbeat_key, ...) — never a user or installation identifier.

CREATE OR REPLACE VIEW bi_observability_incidents AS
SELECT
  id                                                     AS incident_id,
  source                                                 AS source,
  check_key                                              AS check_key,
  title                                                  AS title,
  description                                            AS description,
  severity                                               AS severity,
  status                                                 AS status,
  first_detected_at                                      AS first_detected_at,
  last_detected_at                                       AS last_detected_at,
  acknowledged_at                                        AS acknowledged_at,
  resolved_at                                            AS resolved_at,
  occurrence_count                                       AS occurrence_count,
  notification_count                                     AS notification_count,
  current_value                                          AS current_value,
  threshold_value                                        AS threshold_value,
  dimensions                                             AS dimensions,

  ROUND(
    EXTRACT(EPOCH FROM (COALESCE(resolved_at, NOW()) - first_detected_at))::numeric / 60,
    2
  )                                                      AS duration_minutes,

  (resolved_at IS NOT NULL)                              AS is_resolved,

  (first_detected_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date AS opened_date,
  (resolved_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date       AS resolved_date
FROM observability_incidents
ORDER BY first_detected_at DESC;
