-- bi_observability_heartbeats
--
-- Current state of every monitored recurring process. Not a time series: it
-- answers "what is running right now, and what stopped?".
--
-- calculated_status mirrors ObservabilityHeartbeat#status exactly, including
-- the case that matters most: a heartbeat that has NEVER succeeded but is still
-- inside its first expected interval is 'insufficient_data', not 'critical' —
-- otherwise every fresh deploy would light up the whole board.
--
-- The multipliers (1.5x warning, 2x critical) are Observability::Config
-- defaults. A view cannot read ENV, so overriding them in the app makes this
-- view drift; see docs/observability/BI_VIEWS.md.

CREATE OR REPLACE VIEW bi_observability_heartbeats AS
SELECT
  key                                                    AS key,
  category                                               AS category,
  expected_interval_seconds                              AS expected_interval_seconds,
  last_started_at                                        AS last_started_at,
  last_succeeded_at                                      AS last_succeeded_at,
  last_failed_at                                         AS last_failed_at,
  last_duration_ms                                       AS last_duration_ms,
  consecutive_failures                                   AS consecutive_failures,
  last_error_code                                        AS last_error_code,
  created_at                                             AS created_at,
  updated_at                                             AS updated_at,

  -- NULL (not 0) when the process has never succeeded.
  CASE
    WHEN last_succeeded_at IS NULL THEN NULL
    ELSE EXTRACT(EPOCH FROM (NOW() - last_succeeded_at))::bigint
  END                                                    AS seconds_since_success,

  CASE
    WHEN last_succeeded_at IS NULL
         AND EXTRACT(EPOCH FROM (NOW() - created_at)) <= expected_interval_seconds
      THEN 'insufficient_data'
    WHEN last_succeeded_at IS NULL
      THEN 'critical'
    WHEN EXTRACT(EPOCH FROM (NOW() - last_succeeded_at)) > expected_interval_seconds * 2
      THEN 'critical'
    WHEN EXTRACT(EPOCH FROM (NOW() - last_succeeded_at)) > expected_interval_seconds * 1.5
      THEN 'warning'
    ELSE 'healthy'
  END                                                    AS calculated_status
FROM observability_heartbeats
ORDER BY key;
