require "rails_helper"

RSpec.describe WorkoutPlanGeneratorService do
  it "supports one weekly session and maps detailed locations to conservative legacy behavior" do
    user = create(:user)
    create(:health_profile, user: user, training_days_per_week: 1, training_location: "hotel_travel")

    service = described_class.new(user)

    expect(service.instance_variable_get(:@days_per_week)).to eq(1)
    expect(service.instance_variable_get(:@training_location)).to eq("home")
    expect(described_class::DAY_SCHEDULE.fetch(1)).to eq([ 1 ])
  end

  it "persists an auditable strategy while preserving legacy templates when the flag is off" do
    user = create(:user)
    create(:health_profile, user: user, training_days_per_week: 1, training_location: "home", available_equipment: [ "bodyweight" ])
    create_browseable_exercise("Flexão segura", "chest")
    create_browseable_exercise("Remada segura", "back")
    create_browseable_exercise("Agachamento seguro", "legs")
    create_browseable_exercise("Prancha segura", "core")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "full_body").call

    expect(plan.workout_strategy).to be_present
    expect(plan.workout_strategy.strategy_version).to eq("v1")
    expect(plan.workout_days.first.name).to eq("Full Body")
  end

  it "ignores non-gifdotreino exercises when assigning a workout plan" do
    user = create(:user)
    create(:health_profile, user: user, training_days_per_week: 1, training_location: "full_gym")
    valid = create_browseable_exercise("Supino seguro", "chest")
    Exercise.create!(
      name: "Supino JPG",
      exercise_type: "musculacao",
      muscle_group: "chest",
      equipment_type: "gym",
      image_url: "/exercise-images/db/Bench/0.jpg"
    )
    create_browseable_exercise("Remada segura", "back")
    create_browseable_exercise("Agachamento seguro", "legs")
    create_browseable_exercise("Prancha segura", "core")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "full_body").call

    assigned_ids = plan.workout_days.flat_map { |day| day.workout_day_exercises.pluck(:exercise_id) }
    expect(assigned_ids).to include(valid.id)
    expect(Exercise.where(id: assigned_ids).pluck(:gif_url)).to all(start_with("/exercise-images/gifdotreino/"))
  end

  it "uses the local strategy, excludes safety tags and avoids AI planning when enabled" do
    user = create(:user)
    health_profile = create(
      :health_profile,
      user: user,
      fitness_level: "beginner",
      training_days_per_week: 1,
      training_location: "home",
      available_equipment: [ "bodyweight" ],
      training_context: "pregnant"
    )
    dangerous = create_browseable_exercise("Salto arriscado", "legs", safety_tags: [ "high_impact" ])
    avoided = create_browseable_exercise("Flexão evitada", "chest")
    health_profile.update!(avoided_exercise_ids: [ avoided.id ])
    create_browseable_exercise("Remada segura", "back")
    create_browseable_exercise("Agachamento seguro", "legs")
    create_browseable_exercise("Prancha segura", "core")
    fitness_profile = FitnessProfile.create!(
      user: user,
      fitness_level: "beginner",
      risk_score: 8,
      avoided_exercises: [ avoided.id ],
      metadata: {
        "coach_engine" => {
          "risk" => { "forbidden_exercise_patterns" => [ "high_impact" ], "required_regressions" => [] },
          "behavior" => {},
          "progress" => {}
        }
      }
    )

    allow(FitnessIntelligence).to receive(:enabled?).and_return(true)
    expect(AiAgents::WorkoutPlannerService).not_to receive(:new)

    plan = described_class.new(user, modality: "ai_choice").call
    exercise_ids = plan.workout_days.flat_map { |day| day.workout_day_exercises.pluck(:exercise_id) }

    expect(plan.workout_strategy.fitness_profile).to eq(fitness_profile)
    expect(plan.workout_strategy.strategy["training_split"]).to eq("full_body")
    expect(exercise_ids).not_to include(dangerous.id, avoided.id)
    expect(health_profile.reload).to be_present
  end

  it "applies confident behavior to active frequency and session size" do
    user = create(:user)
    create(
      :health_profile,
      user: user,
      fitness_level: "intermediate",
      training_days_per_week: 4,
      training_location: "home",
      available_equipment: [ "bodyweight" ],
      session_duration_minutes: 60
    )
    %w[chest back legs core].each { |group| create_browseable_exercise("Seguro #{group}", group) }
    FitnessProfile.create!(
      user: user,
      fitness_level: "intermediate",
      behavior_pattern: "low_adherence",
      last_recalculated_at: Time.current,
      metadata: {
        "coach_engine" => {
          "behavior" => {
            "confidence" => 0.8,
            "preferred_patterns" => [ "consistent_short_sessions" ],
            "avoided_patterns" => []
          },
          "risk" => {},
          "progress" => {}
        }
      }
    )

    allow(FitnessIntelligence).to receive(:enabled?).and_return(true)
    plan = described_class.new(user, modality: "ai_choice").call

    expect(plan.workout_strategy.strategy).to include(
      "weekly_frequency" => 3,
      "session_duration_minutes" => 35
    )
    expect(plan.workout_days.count).to eq(3)
    expect(plan.workout_days.all? { |day| day.workout_day_exercises.count <= 5 }).to be(true)
  end

  def create_browseable_exercise(name, muscle_group, safety_tags: [])
    Exercise.create!(
      name: name,
      exercise_type: "musculacao",
      muscle_group: muscle_group,
      equipment_type: "bodyweight",
      difficulty_level: "beginner",
      home_compatible: true,
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif",
      safety_tags: safety_tags
    )
  end
end
