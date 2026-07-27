class AddLinkSignalsToAppInstallations < ActiveRecord::Migration[8.1]
  # Minimal signals to measure the installation -> user link funnel.
  #
  # Without first_authenticated_request_at there is no way to tell an install
  # that never authenticated (an activation problem) from one that authenticated
  # and failed to link (a tracking bug). Every anonymous install today looks the
  # same, so the link rate cannot be interpreted.
  #
  # Backfilling is deliberately NOT done: these columns describe what the backend
  # actually observed, and inventing values for past installs would destroy the
  # only honest baseline we get.
  #
  # No index is added on purpose: the table holds a few hundred rows and every
  # planned query is a full scan either way. Revisit past ~50k rows.
  def up
    # First time the backend saw, in the same request: a current_user, a valid
    # installation_id and an existing AppInstallation for it. Independent of
    # whether the link then succeeded.
    add_column :app_installations, :first_authenticated_request_at, :datetime

    # Link attempts that reached the decision step of AppInstallations::LinkToUser.
    add_column :app_installations, :first_link_attempt_at, :datetime
    add_column :app_installations, :last_link_attempt_at, :datetime

    # First successful link. Never rewritten afterwards.
    add_column :app_installations, :linked_at, :datetime

    add_column :app_installations, :link_attempts_count, :integer, null: false, default: 0

    # Last link failure (e.g. "user_conflict"). Cleared on a successful link.
    add_column :app_installations, :last_link_failure_code, :string

    # Where the linking request came from. Descriptive only — never an eligibility
    # rule. See AppInstallation::RUNTIME_CONTEXTS.
    add_column :app_installations, :runtime_context, :string

    Observability::BiViews.apply!
  end

  def down
    Observability::BiViews.drop!

    remove_column :app_installations, :runtime_context, :string
    remove_column :app_installations, :last_link_failure_code, :string
    remove_column :app_installations, :link_attempts_count, :integer
    remove_column :app_installations, :linked_at, :datetime
    remove_column :app_installations, :last_link_attempt_at, :datetime
    remove_column :app_installations, :first_link_attempt_at, :datetime
    remove_column :app_installations, :first_authenticated_request_at, :datetime

    Observability::BiViews.apply!(skip_unready: true)
  end
end
