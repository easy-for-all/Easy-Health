# Indexes the observability checks depend on. Each one backs a specific query
# documented in docs/observability/ALERT_MATRIX.md; none of them existed before.
class AddObservabilityIndexes < ActiveRecord::Migration[8.1]
  def change
    # android_registration_conversion / android_installation_link_rate group
    # installs by platform over a time window. Only (platform) and
    # (last_seen_at) existed, so the window scan had no supporting index.
    add_index :app_installations, [ :platform, :created_at ],
              if_not_exists: true

    # authenticated_without_installation_link looks for a state that should be
    # impossible: authenticated but unlinked. Partial index, so it stays tiny —
    # in a healthy database it indexes zero rows.
    add_index :app_installations, :last_authenticated_at,
              where: "user_id IS NULL",
              name: "index_app_installations_unlinked_authenticated",
              if_not_exists: true

    # stripe_webhook_failure filters unprocessed events in a recent window.
    # stripe_events only had the unique index on stripe_event_id.
    add_index :stripe_events, [ :status, :processed_at ],
              if_not_exists: true
  end
end
