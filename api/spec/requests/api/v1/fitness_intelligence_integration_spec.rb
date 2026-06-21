require "rails_helper"

RSpec.describe "Fitness intelligence integration", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "creates and refreshes a fitness profile through the health profile flow without changing its response" do
    generator = instance_double(WorkoutPlanGeneratorService, call: nil)
    allow(WorkoutPlanGeneratorService).to receive(:new).and_return(generator)

    post "/api/v1/health_profile", params: valid_health_profile_params

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include("goal" => "gain_muscle")
    expect(user.reload.fitness_profile).to be_present

    sign_in user
    patch "/api/v1/health_profile", params: { training_days_per_week: 4 }

    expect(response).to have_http_status(:ok)
    expect(user.reload.fitness_profile.metadata["last_recalculation_source"]).to eq("health_profile_updated")
  end

  it "refreshes the profile when a workout session is completed" do
    create(:health_profile, user: user)
    FitnessIntelligence::ProfileBuilder.new(user).call(source: "spec_setup")

    post "/api/v1/workout_sessions", params: {
      duration_minutes: 30,
      completed_at: Time.current.iso8601,
      exercise_logs: [ { exercise_id: 1, name: "Teste", sets: 3, reps: [ 10, 10, 10 ] } ]
    }

    expect(response).to have_http_status(:created)
    expect(user.reload.fitness_profile.metadata["last_recalculation_source"]).to eq("workout_completed")
  end

  it "refreshes the profile when an exercise is favorited" do
    create(:health_profile, user: user)
    FitnessIntelligence::ProfileBuilder.new(user).call(source: "spec_setup")
    exercise = Exercise.create!(name: "Puxada", exercise_type: "musculacao", muscle_group: "back")

    post "/api/v1/exercises/#{exercise.id}/favorite"

    expect(response).to have_http_status(:ok)
    profile = user.reload.fitness_profile
    expect(profile.preferred_exercises).to include(exercise.id)
    expect(profile.metadata["last_recalculation_source"]).to eq("favorite_exercise_added")
  end

  it "persists declared preferences, syncs favorites, and refreshes the same fitness profile" do
    generator = instance_double(WorkoutPlanGeneratorService, call: nil)
    allow(WorkoutPlanGeneratorService).to receive(:new).and_return(generator)
    favorite = Exercise.create!(name: "Supino", exercise_type: "musculacao", muscle_group: "chest")
    avoided = Exercise.create!(name: "Burpee", exercise_type: "funcional", muscle_group: "core")

    post "/api/v1/health_profile", params: valid_health_profile_params.merge(
      goal: "strength",
      training_location: "gym",
      training_days_per_week: 1,
      preferred_body_focus: [ "chest", "shoulders" ],
      preferred_training_styles: [ "traditional_strength" ],
      available_equipment: [ "dumbbell" ],
      session_duration_minutes: 25,
      intensity_preference: "progressive",
      favorite_exercise_ids: [ favorite.id ],
      avoided_exercise_ids: [ avoided.id ]
    )

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to include("training_location" => "full_gym", "favorite_exercise_ids" => [ favorite.id ])

    profile = user.reload.health_profile
    fitness_profile = user.fitness_profile
    expect(profile.avoided_exercise_ids).to eq([ avoided.id ])
    expect(user.favorite_exercises).to contain_exactly(favorite)
    expect(fitness_profile.preferred_body_focus).to eq([ "chest", "shoulders" ])
    expect(fitness_profile.avoided_exercises).to eq([ avoided.id ])
    expect(fitness_profile.metadata.to_json).not_to include("Supino")
  end

  it "keeps favorites when an update omits favorite_exercise_ids" do
    health_profile = create(:health_profile, user: user)
    favorite = Exercise.create!(name: "Leg press", exercise_type: "musculacao", muscle_group: "legs")
    user.user_favorite_exercises.create!(exercise: favorite)
    FitnessIntelligence::ProfileBuilder.new(user).call(source: "spec_setup")

    patch "/api/v1/health_profile", params: { training_days_per_week: 1, training_location: "any" }

    expect(response).to have_http_status(:ok)
    expect(user.reload.health_profile.training_location).to eq("unknown")
    expect(user.favorite_exercises).to contain_exactly(favorite)
    expect(health_profile.reload.training_days_per_week).to eq(1)
  end

  it "clears the added preference fields with optional health profile data" do
    health_profile = create(
      :health_profile,
      user: user,
      preferred_body_focus: [ "glutes" ],
      available_equipment: [ "dumbbell" ],
      avoided_exercise_ids: [ 99 ],
      session_duration_minutes: 35,
      intensity_preference: "balanced",
      training_context: "postpartum"
    )
    exercise = Exercise.create!(name: "Puxada limpa", exercise_type: "musculacao", muscle_group: "back")
    user.user_favorite_exercises.create!(exercise: exercise)

    delete "/api/v1/profile/data", params: { data_types: [ "health_profile_optional" ] }

    expect(response).to have_http_status(:ok)
    expect(health_profile.reload).to have_attributes(
      preferred_body_focus: [],
      available_equipment: [],
      avoided_exercise_ids: [],
      session_duration_minutes: nil,
      intensity_preference: nil,
      training_context: nil
    )
    expect(user.favorite_exercises).to be_empty
  end

  it "returns a non-sensitive strategy summary only when the intelligence flag is enabled" do
    plan = user.workout_plans.create!(active: true)
    WorkoutStrategy.create!(
      user: user,
      workout_plan: plan,
      strategy: {
        "strategy_version" => "v1",
        "training_split" => "full_body",
        "primary_focus" => [ "legs", "back" ],
        "user_facing_explanation" => "Plano equilibrado com progressão gradual."
      }
    )
    allow(FitnessIntelligence).to receive(:enabled?).and_return(true)

    get "/api/v1/workout_plan"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("strategy", "training_split")).to eq("full_body")
    expect(body.dig("strategy", "user_facing_explanation")).to eq("Plano equilibrado com progressão gradual.")
  end

  it "creates one strategy per plan during onboarding and active regeneration" do
    create_strategy_catalog
    allow(FitnessIntelligence).to receive(:enabled?).and_return(true)
    expect(AiAgents::WorkoutPlannerService).not_to receive(:new)

    post "/api/v1/health_profile", params: valid_health_profile_params

    expect(response).to have_http_status(:created)
    first_plan = user.reload.active_workout_plan
    expect(first_plan.workout_strategy).to have_attributes(
      fitness_profile: user.fitness_profile,
      strategy_version: "v1"
    )

    sign_in user
    post "/api/v1/workout_plan/regenerate", params: {
      training_days_per_week: 1,
      modality: "ai_choice",
      training_location: "home",
      activity_preferences: [ "musculacao" ]
    }

    expect(response).to have_http_status(:ok)
    current_plan = user.reload.active_workout_plan
    strategy = JSON.parse(response.body).fetch("strategy")
    expect(current_plan).not_to eq(first_plan)
    expect(current_plan.workout_strategy.fitness_profile).to eq(user.fitness_profile)
    expect(user.workout_plans.joins(:workout_strategy).count).to eq(2)
    expect(strategy.keys).to contain_exactly("version", "training_split", "primary_focus", "user_facing_explanation")
  end

  private

  def valid_health_profile_params
    {
      age: 30,
      weight_kg: 70,
      height_cm: 175,
      fitness_level: "beginner",
      goal: "gain_muscle",
      training_days_per_week: 3,
      training_location: "gym",
      activity_preferences: [ "musculacao" ]
    }
  end

  def create_strategy_catalog
    %w[chest back legs core].each do |muscle_group|
      Exercise.create!(
        name: "Estratégia #{muscle_group}",
        exercise_type: "musculacao",
        muscle_group: muscle_group,
        equipment_type: "bodyweight",
        difficulty_level: "beginner",
        home_compatible: true,
        gif_url: "/exercise-images/#{muscle_group}.gif"
      )
    end
  end
end
