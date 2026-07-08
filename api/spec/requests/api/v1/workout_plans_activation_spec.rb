require "rails_helper"

RSpec.describe "Api::V1::WorkoutPlans activation tracking", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }

  before { sign_in user }

  def stub_generated_plan(name: "Full Body A")
    allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:call) do
      new_plan = user.workout_plans.create!(active: true)
      new_day = new_plan.workout_days.create!(name: name, day_of_week: Date.current.wday)
      new_day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)
      new_plan
    end
    allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:plan_summary).and_return({})
  end

  it "tracks activation_workout_created with workout metadata on the user's first plan" do
    stub_generated_plan

    post "/api/v1/workout_plan/regenerate", params: { modality: "ai_choice" }

    expect(response).to have_http_status(:ok)
    plan_id = user.reload.active_workout_plan.id
    event = UserEvent.find_by(user: user, event_name: "activation_workout_created")

    expect(event).to be_present
    expect(event.idempotency_key).to eq("activation_workout_created:#{user.id}:#{plan_id}")
    expect(event.metadata.dig("workout", "name")).to eq("Full Body A")
    expect(event.metadata.dig("workout", "exercises_count")).to eq(1)
    expect(event.metadata.dig("workout", "muscle_groups")).to eq([ "biceps" ])
    expect(event.metadata.dig("activation", "has_started_workout")).to eq(false)
    expect(event.metadata.dig("activation", "has_completed_first_workout")).to eq(false)
  end

  it "does not duplicate activation_workout_created on a later regenerate" do
    stub_generated_plan
    post "/api/v1/workout_plan/regenerate", params: { modality: "ai_choice" }
    expect(UserEvent.where(user: user, event_name: "activation_workout_created").count).to eq(1)

    stub_generated_plan(name: "Full Body B")
    post "/api/v1/workout_plan/regenerate", params: { modality: "ai_choice" }

    expect(UserEvent.where(user: user, event_name: "activation_workout_created").count).to eq(1)
  end
end
