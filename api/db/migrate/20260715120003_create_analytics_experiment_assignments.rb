class CreateAnalyticsExperimentAssignments < ActiveRecord::Migration[8.1]
  # Minimal base for future experiments (push vs control, CTA, onboarding, etc.).
  # No decision engine now — persistence only, so exposure/conversion can be
  # measured later without a schema change. Named analytics_* to avoid clashing
  # with the existing activation-push ExperimentAssignment service.
  def change
    create_table :analytics_experiment_assignments do |t|
      t.string   :experiment_key, null: false
      t.string   :variant,        null: false
      t.references :user, foreign_key: true, index: true
      t.string   :anonymous_id
      t.datetime :assigned_at, null: false
      t.datetime :exposed_at
      t.datetime :converted_at

      t.timestamps
    end

    add_index :analytics_experiment_assignments, [ :experiment_key, :variant ]
    add_index :analytics_experiment_assignments, [ :experiment_key, :user_id ],
              unique: true, where: "user_id IS NOT NULL",
              name: "index_analytics_experiments_unique_user"
    add_index :analytics_experiment_assignments, [ :experiment_key, :anonymous_id ],
              unique: true, where: "user_id IS NULL AND anonymous_id IS NOT NULL",
              name: "index_analytics_experiments_unique_anon"
  end
end
