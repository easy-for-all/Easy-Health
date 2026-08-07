require "rails_helper"
require Rails.root.join("db/migrate/20260804130000_add_installation_owner_to_workout_plans").to_s

# Esta migration derrubou a API de produção duas vezes: primeiro por assumir que
# um índice existia, depois por assumir que os dados o respeitavam. O spec exige
# que ela sobreviva às duas coisas.
RSpec.describe AddInstallationOwnerToWorkoutPlans do
  let(:connection) { ActiveRecord::Base.connection }

  # Devolve workout_plans ao estado ANTERIOR à migration, que é o estado em que
  # uma base antiga (produção antes de 04/08, ou uma instalação parada) está.
  # Sem o índice único e sem o app_installation_id.
  def rewind_schema!
    connection.remove_index :workout_plans, name: "index_workout_plans_one_active_per_installation", if_exists: true
    connection.remove_index :workout_plans, name: "index_workout_plans_one_active_per_user", if_exists: true
    connection.remove_check_constraint :workout_plans, name: "workout_plans_single_owner", if_exists: true
    connection.remove_reference :workout_plans, :app_installation, foreign_key: true if connection.column_exists?(:workout_plans, :app_installation_id)
    connection.change_column_null :workout_plans, :user_id, false

    WorkoutPlan.reset_column_information
  end

  def insert_legacy_plan(user_id:, created_at:)
    connection.select_value(<<~SQL.squish)
      INSERT INTO workout_plans (user_id, active, created_at, updated_at)
      VALUES (#{user_id}, true, #{connection.quote(created_at)}, #{connection.quote(created_at)})
      RETURNING id
    SQL
  end

  def index_names
    connection.indexes(:workout_plans).map(&:name)
  end

  after { WorkoutPlan.reset_column_information }

  it "runs on a legacy base that never had the unique index" do
    rewind_schema!
    expect(index_names).not_to include("index_workout_plans_one_active_per_user")

    expect { described_class.new.up }.not_to raise_error

    expect(index_names).to include(
      "index_workout_plans_one_active_per_user",
      "index_workout_plans_one_active_per_installation"
    )
  end

  it "deactivates legacy duplicates instead of failing, keeping the most recent plan" do
    user = create(:user)
    rewind_schema!

    base = Time.zone.parse("2026-07-01 10:00:00")
    older = insert_legacy_plan(user_id: user.id, created_at: base)
    newer = insert_legacy_plan(user_id: user.id, created_at: base + 4.seconds)

    expect { described_class.new.up }.not_to raise_error

    WorkoutPlan.reset_column_information
    expect(WorkoutPlan.where(user_id: user.id, active: true).pluck(:id)).to eq([ newer ])
    expect(WorkoutPlan.find(older).active).to be(false)
  end

  it "never deletes a historical plan while reconciling" do
    user = create(:user)
    rewind_schema!

    base = Time.zone.parse("2026-07-01 10:00:00")
    ids = [
      insert_legacy_plan(user_id: user.id, created_at: base),
      insert_legacy_plan(user_id: user.id, created_at: base + 2.seconds),
      insert_legacy_plan(user_id: user.id, created_at: base + 5.seconds)
    ]

    described_class.new.up

    WorkoutPlan.reset_column_information
    expect(WorkoutPlan.where(id: ids).count).to eq(3)
    expect(WorkoutPlan.where(id: ids, active: true).count).to eq(1)
  end

  # O desempate por id existe porque os duplicados reais nasceram no MESMO
  # segundo: created_at sozinho não escolhe um vencedor determinístico.
  it "breaks a created_at tie by id, deterministically" do
    user = create(:user)
    rewind_schema!

    same_instant = Time.zone.parse("2026-07-01 10:00:00")
    first  = insert_legacy_plan(user_id: user.id, created_at: same_instant)
    second = insert_legacy_plan(user_id: user.id, created_at: same_instant)

    described_class.new.up

    WorkoutPlan.reset_column_information
    expect(WorkoutPlan.where(user_id: user.id, active: true).pluck(:id)).to eq([ [ first, second ].max ])
  end
end
