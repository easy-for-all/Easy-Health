class AddInstallationIdToAnalyticsExperimentAssignments < ActiveRecord::Migration[8.1]
  # The pre-auth Android experiment is decided before an account exists AND
  # before anonymous_id is a useful key: anonymous_id (eh_anon_id, localStorage)
  # is the analytics identity and has its own column in product_analytics_events.
  # Storing an installation_id in it would make every future join silently lie
  # about which identity it is talking about.
  #
  # installation_id is the unit of the whole Android panel (AndroidFunnel groups
  # by properties->>'installation_id'), so it is what the experiment must key on
  # to be joinable with the funnel it is meant to move.
  def change
    add_column :analytics_experiment_assignments, :installation_id, :string

    # Partial and disjoint from the two existing unique indexes: a row belongs to
    # exactly one identity space. This index is what makes "one installation, one
    # variant" an invariant of the database instead of a convention of the client
    # — the endpoint relies on it for ON CONFLICT DO NOTHING.
    add_index :analytics_experiment_assignments, [ :experiment_key, :installation_id ],
              unique: true, where: "user_id IS NULL AND installation_id IS NOT NULL",
              name: "index_analytics_experiments_unique_installation"
  end
end
