require "rails_helper"
require "rake"

RSpec.describe "exercise_execution:backfill" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("exercise_execution:backfill")
  end

  let(:task) { Rake::Task["exercise_execution:backfill"] }
  let(:user) { create(:user) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }
  let(:cardio_exercise) { Exercise.create!(name: "Corrida", exercise_type: "corrida") }

  before do
    task.reenable
    ENV.delete("USER_ID")
  end

  after { ENV.delete("USER_ID") }

  it "creates exercise_sessions/exercise_sets from a strength exercise log with parallel arrays" do
    session = user.workout_sessions.create!(
      completed_at: 2.days.ago,
      duration_minutes: 40,
      exercise_logs: [ {
        "exercise_id" => exercise.id,
        "name" => exercise.name,
        "weight_by_set" => [ 10, 15, 15 ],
        "reps" => [ 12, 10, 8 ],
        "is_warmup_by_set" => [ true, false, false ],
        "planned_sets" => 3
      } ]
    )

    expect { task.invoke }.to output(/1 processed, 0 failed, 0 skipped.*1 exercise_sessions, 3 exercise_sets/).to_stdout

    exercise_session = session.reload.exercise_sessions.sole
    expect(exercise_session.exercise_kind).to eq("strength")
    expect(exercise_session.exercise_sets.order(:set_number).pluck(:weight_kg, :reps, :is_warmup)).to eq(
      [ [ 10.0, 12, true ], [ 15.0, 10, false ], [ 15.0, 8, false ] ]
    )
  end

  it "is idempotent - running it twice does not duplicate rows" do
    user.workout_sessions.create!(
      completed_at: 1.day.ago,
      duration_minutes: 30,
      exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 20 ], "reps" => [ 10 ], "is_warmup_by_set" => [ false ] } ]
    )

    task.invoke
    task.reenable
    expect { task.invoke }.to output(/0 processed, 0 failed/).to_stdout

    expect(ExerciseSession.count).to eq(1)
    expect(ExerciseSet.count).to eq(1)
  end

  it "handles arrays with mismatched lengths without raising" do
    session = user.workout_sessions.create!(
      completed_at: 1.day.ago,
      duration_minutes: 30,
      exercise_logs: [ {
        "exercise_id" => exercise.id,
        "weight_by_set" => [ 10, 12 ],
        "reps" => [ 8 ],
        "is_warmup_by_set" => []
      } ]
    )

    expect { task.invoke }.to output(/1 processed, 0 failed/).to_stdout

    sets = session.reload.exercise_sessions.sole.exercise_sets.order(:set_number)
    expect(sets.size).to eq(2)
    expect(sets.last.reps).to be_nil
  end

  it "creates only an exercise_session (no sets) for cardio logs" do
    session = user.workout_sessions.create!(
      completed_at: 1.day.ago,
      duration_minutes: 30,
      exercise_logs: [ { "exercise_id" => cardio_exercise.id, "duration_minutes" => 20, "intensity" => "moderado" } ]
    )

    task.invoke

    exercise_session = session.reload.exercise_sessions.sole
    expect(exercise_session.exercise_kind).to eq("cardio")
    expect(exercise_session.exercise_sets).to be_empty
  end

  it "skips logs with a missing or deleted exercise without failing the whole session" do
    user.workout_sessions.create!(
      completed_at: 1.day.ago,
      duration_minutes: 30,
      exercise_logs: [
        { "exercise_id" => nil, "weight_by_set" => [ 10 ], "reps" => [ 10 ] },
        { "exercise_id" => exercise.id, "weight_by_set" => [ 10 ], "reps" => [ 10 ], "is_warmup_by_set" => [ false ] }
      ]
    )

    expect { task.invoke }.to output(/1 processed, 0 failed, 1 skipped.*1 exercise_sessions/).to_stdout
    expect(ExerciseSession.count).to eq(1)
  end

  it "filters by USER_ID when provided" do
    other_user = create(:user)
    user.workout_sessions.create!(completed_at: 1.day.ago, duration_minutes: 30, exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 10 ], "reps" => [ 10 ] } ])
    other_user.workout_sessions.create!(completed_at: 1.day.ago, duration_minutes: 30, exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 10 ], "reps" => [ 10 ] } ])

    ENV["USER_ID"] = user.id.to_s
    expect { task.invoke }.to output(/1 processed, 0 failed/).to_stdout

    expect(ExerciseSession.where(workout_session: user.workout_sessions).count).to eq(1)
    expect(ExerciseSession.where(workout_session: other_user.workout_sessions).count).to eq(0)
  end
end
