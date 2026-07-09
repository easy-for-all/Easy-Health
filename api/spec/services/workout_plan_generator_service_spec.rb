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

  it "builds the plan from a chat_decision instead of the rule-based/AI templates" do
    user = create(:user)
    create(:health_profile, user: user, training_days_per_week: 5, training_location: "full_gym")
    %w[chest back shoulders legs core].each { |group| create_browseable_exercise("Seguro #{group}", group) }

    chat_decision = {
      training_method: "upper_lower",
      plan_name: "Plano do Chat",
      rationale: "Motivo do chat.",
      week_structure: [
        { name: "Superior", muscle_groups: %w[chest back shoulders] },
        { name: "Inferior", muscle_groups: %w[legs core] }
      ],
      sets_reps: { sets: 3, reps: 12, rest_seconds: 60 },
      progression_strategy: "Progressão do chat.",
      safety_notes: ["Nota de segurança do chat"]
    }

    allow(FitnessIntelligence).to receive(:enabled?).and_return(true)
    expect(AiAgents::WorkoutPlannerService).not_to receive(:new)

    plan = described_class.new(user, chat_decision: chat_decision).call

    expect(plan.workout_days.count).to eq(2)
    expect(plan.workout_days.pluck(:name)).to contain_exactly("Superior", "Inferior")
    exercise = plan.workout_days.first.workout_day_exercises.first
    expect(exercise.sets).to eq(3)
    expect(exercise.reps).to eq(12)
    expect(exercise.rest_seconds).to eq(60)

    log = AiTrainingDecisionLog.find_by(workout_plan_id: plan.id)
    expect(log.training_method).to eq("upper_lower")
    expect(log.model_used).to eq(AiConfig.for(:workout_chat_plan_generation)[:model])
  end

  it "keeps the generated plan when non-critical decision log persistence fails" do
    user = create(:user)
    create(:health_profile, user: user, training_days_per_week: 1, training_location: "full_gym")
    %w[chest back legs core].each { |group| create_browseable_exercise("Seguro #{group}", group) }

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    allow(AiTrainingDecisionLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new("PG failure"))

    plan = described_class.new(user, modality: "musculacao", split_type: "full_body").call

    expect(plan).to be_persisted
    expect(plan.workout_days.count).to eq(1)
    expect(plan.workout_days.first.workout_day_exercises.count).to be_positive
  end

  it "Teste 1: advanced/gain_muscle 3x/45min full_gym allows advanced exercises with coherent volume and split" do
    user = create(:user)
    create(:health_profile, user: user, fitness_level: "advanced", goal: "gain_muscle",
      training_days_per_week: 3, training_location: "full_gym", session_duration_minutes: 45,
      split_type: "abc", modality: "musculacao")

    advanced_back = create_browseable_exercise("Barra Fixa Teste", "back",
      calisthenics_skill: "advanced", technical_complexity: "high", risk_level: "high")
    create_browseable_exercise("Peito seguro", "chest")
    create_browseable_exercise("Ombro seguro", "shoulders")
    create_browseable_exercise("Triceps seguro", "triceps")
    create_browseable_exercise("Biceps seguro", "biceps")
    create_browseable_exercise("Perna segura", "legs")
    create_browseable_exercise("Core seguro", "core")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "abc").call

    expect(plan.workout_days.count).to eq(3)
    exercise_ids = plan.workout_days.flat_map { |d| d.workout_day_exercises.pluck(:exercise_id) }
    expect(exercise_ids).to include(advanced_back.id)
    expect(plan.workout_days.sum { |d| d.workout_day_exercises.count }).to be > 0
  end

  it "Teste 2: beginner/gain_muscle 3x/60min never selects Muscle Up or unassisted Barra Fixa" do
    user = create(:user)
    create(:health_profile, user: user, fitness_level: "beginner", goal: "gain_muscle",
      training_days_per_week: 3, training_location: "full_gym", session_duration_minutes: 60,
      split_type: "abc", modality: "musculacao")

    muscle_up = create_browseable_exercise("Muscle Up", "back",
      calisthenics_skill: "advanced", technical_complexity: "high", risk_level: "high")
    barra_fixa = create_browseable_exercise("Barra Fixa", "back",
      calisthenics_skill: "basic", technical_complexity: "medium", risk_level: "medium")
    assisted = create_browseable_exercise("Barra Fixa Assistida", "back",
      calisthenics_skill: "none", technical_complexity: "low", risk_level: "low")
    create_browseable_exercise("Peito seguro", "chest")
    create_browseable_exercise("Ombro seguro", "shoulders")
    create_browseable_exercise("Triceps seguro", "triceps")
    create_browseable_exercise("Biceps seguro", "biceps")
    create_browseable_exercise("Perna segura", "legs")
    create_browseable_exercise("Core seguro", "core")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "abc").call

    exercise_ids = plan.workout_days.flat_map { |d| d.workout_day_exercises.pluck(:exercise_id) }
    expect(exercise_ids).not_to include(muscle_up.id, barra_fixa.id)
    expect(exercise_ids).to include(assisted.id)
  end

  it "Teste 3: strength+calisthenics 5x/45min varies reps/rest, keeps legs well-stocked, and calisthenics influences selection" do
    user = create(:user)
    create(:health_profile, user: user, fitness_level: "intermediate", goal: "strength",
      training_days_per_week: 5, training_location: "full_gym", session_duration_minutes: 45,
      split_type: "ai_choice", modality: "musculacao", preferred_training_styles: [ "calisthenics" ],
      intensity_preference: "balanced")

    3.times { |i| create_browseable_exercise("Perna #{i}", "legs", movement_pattern: "squat", compound: true) }
    3.times { |i| create_browseable_exercise("Core #{i}", "core") }
    2.times { |i| create_browseable_exercise("Peito #{i}", "chest") }
    2.times { |i| create_browseable_exercise("Ombro #{i}", "shoulders") }
    2.times { |i| create_browseable_exercise("Triceps #{i}", "triceps") }
    calisthenics_back = create_browseable_exercise("Barra Fixa Calistenia", "back",
      style_tags: [ "calisthenics" ], movement_pattern: "pull", compound: true)
    create_browseable_exercise("Costas segura", "back")
    2.times { |i| create_browseable_exercise("Biceps #{i}", "biceps") }

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    allow_any_instance_of(AiWorkout::DailyLimitChecker).to receive(:limit_reached?).and_return(true)
    expect(AiAgents::WorkoutPlannerService).not_to receive(:new)

    plan = described_class.new(user, modality: "musculacao", split_type: "ai_choice", training_location: "full_gym").call

    expect(plan.workout_days.count).to eq(5)

    leg_ids = Exercise.where(muscle_group: "legs").pluck(:id)
    legs_exercise_count = WorkoutDayExercise.where(workout_day: plan.workout_days, exercise_id: leg_ids).count
    expect(legs_exercise_count).to be >= 3

    all_wdes = WorkoutDayExercise.where(workout_day: plan.workout_days)
    expect(all_wdes.pluck(:reps).uniq.size).to be > 1
    expect(all_wdes.pluck(:rest_seconds).uniq.size).to be > 1
    expect(all_wdes.pluck(:exercise_id)).to include(calisthenics_back.id)
  end

  it "Teste 4: beginner+calisthenics preference never selects Muscle Up and prefers safe bodyweight regressions" do
    user = create(:user)
    create(:health_profile, user: user, fitness_level: "beginner", goal: "gain_muscle",
      training_days_per_week: 3, training_location: "full_gym", session_duration_minutes: 45,
      split_type: "abc", modality: "musculacao", preferred_training_styles: [ "calisthenics" ])

    muscle_up = create_browseable_exercise("Muscle Up", "back",
      calisthenics_skill: "advanced", technical_complexity: "high", risk_level: "high", style_tags: [ "calisthenics" ])
    safe_calisthenics = create_browseable_exercise("Remada Invertida", "back",
      calisthenics_skill: "none", technical_complexity: "low", risk_level: "low", style_tags: [ "calisthenics" ])
    create_browseable_exercise("Peito seguro", "chest")
    create_browseable_exercise("Ombro seguro", "shoulders")
    create_browseable_exercise("Triceps seguro", "triceps")
    create_browseable_exercise("Biceps seguro", "biceps")
    create_browseable_exercise("Perna segura", "legs")
    create_browseable_exercise("Core seguro", "core")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "abc").call

    exercise_ids = plan.workout_days.flat_map { |d| d.workout_day_exercises.pluck(:exercise_id) }
    expect(exercise_ids).not_to include(muscle_up.id)
    expect(exercise_ids).to include(safe_calisthenics.id)
  end

  it "Teste 5: PlanValidator substitutes an unsafe exercise injected directly into a beginner's plan" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, fitness_level: "beginner", goal: "gain_muscle",
      training_days_per_week: 1, training_location: "full_gym", session_duration_minutes: 45,
      split_type: "full_body", modality: "musculacao")

    regression = create_browseable_exercise("Barra Fixa Assistida", "back",
      calisthenics_skill: "none", technical_complexity: "low", risk_level: "low")
    muscle_up = create_browseable_exercise("Muscle Up", "back",
      calisthenics_skill: "advanced", technical_complexity: "high", risk_level: "high", regression_exercise: regression)

    # Build a minimal plan by hand (bypassing the generator) so the test
    # controls exactly what's already in the day, simulating a Muscle Up
    # that slipped in via favorites/AI/manual swap.
    plan = WorkoutPlan.create!(user: user, active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Full Body", position: 1)
    bad_wde = day.workout_day_exercises.create!(exercise: muscle_up, sets: 3, reps: 8, rest_seconds: 90, order_index: 0)

    candidate_scope = WorkoutIntelligence::ExerciseCandidateScope.new(
      training_location: "gym", fitness_level: "beginner", strategy: nil,
      available_equipment: [], fav_exercise_ids: []
    )
    volume_planner = WorkoutIntelligence::WeeklyVolumePlanner.new(
      goal: "gain_muscle", fitness_level: "beginner", days_per_week: 1, session_duration_minutes: 45,
      groups_in_template: %w[back]
    )
    volume_planner.call

    validator = WorkoutIntelligence::PlanValidator.new(
      plan: plan, health_profile: health_profile, fitness_level: "beginner", goal: "gain_muscle",
      weekly_volume_targets: volume_planner.targets, candidate_scope: candidate_scope, decision_source: "rule_based"
    )
    result = validator.call

    expect(result.valid).to be(true)
    expect(result.auto_fixes).to include(hash_including(code: :substituted_exercise, from: "Muscle Up", to: "Barra Fixa Assistida"))
    expect(WorkoutDayExercise.find(bad_wde.id).exercise_id).to eq(regression.id)
  end

  def build_validator_for(plan, health_profile, fitness_level:, goal:)
    candidate_scope = WorkoutIntelligence::ExerciseCandidateScope.new(
      training_location: "gym", fitness_level: fitness_level, strategy: nil,
      available_equipment: [], fav_exercise_ids: []
    )
    volume_planner = WorkoutIntelligence::WeeklyVolumePlanner.new(
      goal: goal, fitness_level: fitness_level, days_per_week: 1, session_duration_minutes: 45,
      groups_in_template: %w[back]
    )
    volume_planner.call

    WorkoutIntelligence::PlanValidator.new(
      plan: plan, health_profile: health_profile, fitness_level: fitness_level, goal: goal,
      weekly_volume_targets: volume_planner.targets, candidate_scope: candidate_scope, decision_source: "rule_based"
    )
  end

  it "item 11: dissolves a composite block combining two high-risk exercises for a non-advanced level" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, fitness_level: "intermediate", goal: "gain_muscle",
      training_days_per_week: 1, training_location: "full_gym", session_duration_minutes: 45)

    risky_a = create_browseable_exercise("Risco A", "back", technical_complexity: "high", risk_level: "high")
    risky_b = create_browseable_exercise("Risco B", "back", technical_complexity: "high", risk_level: "high")

    plan = WorkoutPlan.create!(user: user, active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Full Body", position: 1)
    block = day.workout_blocks.create!(block_type: "superset", position: 0, rounds: 3)
    day.workout_day_exercises.create!(exercise: risky_a, sets: 3, reps: 8, rest_seconds: 0, order_index: 0, workout_block: block, position_in_block: 0)
    day.workout_day_exercises.create!(exercise: risky_b, sets: 3, reps: 8, rest_seconds: 0, order_index: 1, workout_block: block, position_in_block: 1)

    result = build_validator_for(plan, health_profile, fitness_level: "intermediate", goal: "gain_muscle").call

    expect(result.auto_fixes).to include(hash_including(code: :dissolved_unsafe_block, reason: "too_many_high_risk_exercises_together"))
    expect(WorkoutDayExercise.where(exercise: [ risky_a, risky_b ]).pluck(:workout_block_id).uniq.size).to eq(2)
    expect(WorkoutBlock.find_by(id: block.id)).to be_nil
  end

  it "item 11: dissolves a circuit larger than allowed for a non-advanced level" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, fitness_level: "intermediate", goal: "conditioning",
      training_days_per_week: 1, training_location: "full_gym", session_duration_minutes: 45)

    exercises = (1..5).map { |i| create_browseable_exercise("Circuito #{i}", "core") }

    plan = WorkoutPlan.create!(user: user, active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Full Body", position: 1)
    block = day.workout_blocks.create!(block_type: "circuit", position: 0, rounds: 3)
    exercises.each_with_index do |ex, idx|
      day.workout_day_exercises.create!(exercise: ex, sets: 1, reps: 12, rest_seconds: 0, order_index: idx, workout_block: block, position_in_block: idx)
    end

    result = build_validator_for(plan, health_profile, fitness_level: "intermediate", goal: "conditioning").call

    expect(result.auto_fixes).to include(hash_including(code: :dissolved_unsafe_block, reason: "circuit_too_large_for_level"))
    expect(WorkoutBlock.find_by(id: block.id)).to be_nil
  end

  it "item 11: dissolves a block combining 2+ compound exercises under a strength goal" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, fitness_level: "advanced", goal: "strength",
      training_days_per_week: 1, training_location: "full_gym", session_duration_minutes: 45)

    squat = create_browseable_exercise("Agachamento Livre", "legs", compound: true, movement_pattern: "squat")
    deadlift = create_browseable_exercise("Levantamento Terra", "back", compound: true, movement_pattern: "hinge")

    plan = WorkoutPlan.create!(user: user, active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Full Body", position: 1)
    block = day.workout_blocks.create!(block_type: "superset", position: 0, rounds: 3)
    day.workout_day_exercises.create!(exercise: squat, sets: 3, reps: 5, rest_seconds: 0, order_index: 0, workout_block: block, position_in_block: 0)
    day.workout_day_exercises.create!(exercise: deadlift, sets: 3, reps: 5, rest_seconds: 0, order_index: 1, workout_block: block, position_in_block: 1)

    result = build_validator_for(plan, health_profile, fitness_level: "advanced", goal: "strength").call

    expect(result.auto_fixes).to include(hash_including(code: :dissolved_unsafe_block, reason: "multiple_compound_exercises_in_strength_block"))
    expect(WorkoutBlock.find_by(id: block.id)).to be_nil
  end

  it "item 11: trimming excess exercises never leaves a composite block below its minimum size" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, fitness_level: "advanced", goal: "conditioning",
      training_days_per_week: 1, training_location: "full_gym", session_duration_minutes: 60)

    plan = WorkoutPlan.create!(user: user, active: true)
    day = plan.workout_days.create!(day_of_week: 1, name: "Full Body", position: 1)

    # (max_singles - 1) leading singles, then a 3-exercise circuit, then 2
    # trailing singles. The trim removes the last 4 by order_index - the 2
    # trailing singles plus the last 2 circuit members - leaving exactly 1
    # circuit member alive. Naively destroying those 2 would leave that
    # survivor stuck in a "circuit" block with only 1 member; it must instead
    # come out the other side as its own "single" block.
    max_singles = WorkoutIntelligence::PlanValidator::MAX_EXERCISES_PER_DAY
    idx = 0
    (max_singles - 1).times do
      ex = create_browseable_exercise("Single #{idx}", "back")
      day.workout_day_exercises.create!(exercise: ex, sets: 3, reps: 10, rest_seconds: 60, order_index: idx)
      idx += 1
    end

    circuit_exercises = (1..3).map { |i| create_browseable_exercise("Circuito Trim #{i}", "core") }
    block = day.workout_blocks.create!(block_type: "circuit", position: idx, rounds: 3)
    circuit_exercises.each_with_index do |ex, position_in_block|
      day.workout_day_exercises.create!(
        exercise: ex, sets: 1, reps: 12, rest_seconds: 0,
        order_index: idx, workout_block: block, position_in_block: position_in_block
      )
      idx += 1
    end

    2.times do
      ex = create_browseable_exercise("Trailing #{idx}", "back")
      day.workout_day_exercises.create!(exercise: ex, sets: 3, reps: 10, rest_seconds: 60, order_index: idx)
      idx += 1
    end

    build_validator_for(plan, health_profile, fitness_level: "advanced", goal: "conditioning").call

    survivor = WorkoutDayExercise.find_by(exercise_id: circuit_exercises.first.id) # circuit_start_index, first to survive the trim
    expect(survivor).to be_present
    expect(survivor.workout_block.block_type).to eq("single")
    expect(WorkoutDayExercise.where(exercise: circuit_exercises[1..])).to be_empty
    expect(WorkoutBlock.find_by(id: block.id)).to be_nil
  end

  it "groups exercises into a composite block when the profile favors it (item 10 - gerador cria blocos)" do
    user = create(:user)
    create(
      :health_profile, user: user, fitness_level: "intermediate", goal: "gain_muscle",
      training_days_per_week: 1, training_location: "home", available_equipment: [ "bodyweight" ],
      session_duration_minutes: 25
    )
    create_browseable_exercise("Flexão segura", "chest")
    create_browseable_exercise("Remada segura", "back")

    allow(FitnessIntelligence).to receive(:enabled?).and_return(false)
    plan = described_class.new(user, modality: "musculacao", split_type: "full_body").call

    blocks = plan.workout_days.flat_map(&:workout_blocks)
    composite = blocks.select { |b| WorkoutBlock::MULTI_EXERCISE_TYPES.include?(b.block_type) }
    expect(composite).not_to be_empty
    expect(composite.first.label).to be_present
    expect(composite.first.workout_day_exercises.count).to eq(2)
  end

  def create_browseable_exercise(name, muscle_group, safety_tags: [], technical_complexity: nil,
                                  risk_level: nil, calisthenics_skill: nil, compound: nil,
                                  movement_pattern: nil, style_tags: [], objective_tags: [],
                                  regression_exercise: nil, equipment_type: "bodyweight", difficulty_level: "beginner")
    Exercise.create!(
      name: name,
      exercise_type: "musculacao",
      muscle_group: muscle_group,
      equipment_type: equipment_type,
      difficulty_level: difficulty_level,
      home_compatible: true,
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif",
      safety_tags: safety_tags,
      technical_complexity: technical_complexity,
      risk_level: risk_level,
      calisthenics_skill: calisthenics_skill,
      compound: compound,
      movement_pattern: movement_pattern,
      style_tags: style_tags,
      objective_tags: objective_tags,
      regression_exercise: regression_exercise
    )
  end
end
