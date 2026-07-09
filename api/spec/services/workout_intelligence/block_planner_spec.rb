require "rails_helper"

RSpec.describe WorkoutIntelligence::BlockPlanner do
  def exercise(name:, **attrs)
    Exercise.create!(
      name: name, exercise_type: "musculacao", muscle_group: "back", equipment_type: "bodyweight",
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif", **attrs
    )
  end

  def pick(exercise, sets: 3, reps: 10, rest_seconds: 60)
    { exercise: exercise, sets: sets, reps: reps, rest_seconds: rest_seconds }
  end

  def call(picks, fitness_level:, goal:, day_exercise_limit: 6)
    described_class.new(picks: picks, fitness_level: fitness_level, goal: goal, day_exercise_limit: day_exercise_limit).call
  end

  it "does not group when there is only one exercise" do
    result = call([ pick(exercise(name: "A")) ], fitness_level: "intermediate", goal: "gain_muscle")
    expect(result.groups).to be_empty
    expect(result.leftovers.size).to eq(1)
  end

  describe "beginner (iniciante não recebe bloco complexo)" do
    it "never creates a circuit, at most one simple superset" do
      picks = [ "A", "B", "C", "D" ].map { |n| pick(exercise(name: n)) }
      result = call(picks, fitness_level: "beginner", goal: "health")

      expect(result.groups.size).to eq(1)
      expect(result.groups.first.block_type).to eq("superset")
      expect(result.groups.first.members.size).to eq(2)
      expect(result.leftovers.size).to eq(2)
    end

    it "excludes high technical_complexity/risk_level exercises from grouping" do
      safe_a = exercise(name: "Safe A")
      safe_b = exercise(name: "Safe B")
      risky  = exercise(name: "Risky", technical_complexity: "high", risk_level: "high")
      picks = [ pick(safe_a), pick(safe_b), pick(risky) ]

      result = call(picks, fitness_level: "beginner", goal: "health")

      grouped_names = result.groups.flat_map(&:members).map { |m| m[:exercise].name }
      expect(grouped_names).not_to include("Risky")
    end
  end

  describe "força (nunca agrupa exercícios principais/compound pesados)" do
    it "excludes compound exercises from any block under a strength goal" do
      compound_lift = exercise(name: "Agachamento Livre", compound: true, movement_pattern: "squat")
      accessory_a   = exercise(name: "Extensora", compound: false, movement_pattern: "isolation")
      accessory_b   = exercise(name: "Flexora", compound: false, movement_pattern: "isolation")
      picks = [ pick(compound_lift), pick(accessory_a), pick(accessory_b) ]

      result = call(picks, fitness_level: "advanced", goal: "strength")

      grouped_names = result.groups.flat_map(&:members).map { |m| m[:exercise].name }
      expect(grouped_names).not_to include("Agachamento Livre")
      expect(result.leftovers.map { |p| p[:exercise].name }).to include("Agachamento Livre")
    end

    it "never puts a compound exercise inside a circuit under a strength goal" do
      compound = exercise(name: "Levantamento Terra", compound: true, movement_pattern: "hinge")
      accessories = [ "Rosca", "Triceps", "Panturrilha" ].map { |n| exercise(name: n, compound: false, movement_pattern: "isolation") }
      picks = [ pick(compound) ] + accessories.map { |ex| pick(ex) }

      result = call(picks, fitness_level: "advanced", goal: "strength")

      circuits = result.groups.select { |g| g.block_type == "circuit" }
      circuits.each do |circuit|
        expect(circuit.members.map { |m| m[:exercise].name }).not_to include("Levantamento Terra")
      end
    end
  end

  describe "hipertrofia (permite superset antagonista/acessório)" do
    it "groups eligible exercises into a superset for intermediate+" do
      picks = [ "Supino", "Remada" ].map { |n| pick(exercise(name: n)) }
      result = call(picks, fitness_level: "intermediate", goal: "gain_muscle")

      expect(result.groups.size).to eq(1)
      expect(result.groups.first.block_type).to eq("superset")
      expect(result.groups.first.rationale).to include("hipertrofia")
    end
  end

  describe "condicionamento (favorece circuito)" do
    it "creates a circuit block for 3+ exercises when goal is conditioning" do
      picks = [ "Prancha", "Abdominal", "Elevação de pernas" ].map { |n| pick(exercise(name: n)) }
      result = call(picks, fitness_level: "intermediate", goal: "conditioning")

      expect(result.groups.size).to eq(1)
      expect(result.groups.first.block_type).to eq("circuit")
      expect(result.groups.first.members.size).to eq(3)
    end
  end

  describe "duração de sessão como proxy" do
    it "allows up to 2 groups in a short session" do
      picks = (1..4).map { |i| pick(exercise(name: "Ex #{i}")) }
      result = call(picks, fitness_level: "intermediate", goal: "gain_muscle", day_exercise_limit: 5)

      expect(result.groups.size).to eq(2)
      expect(result.leftovers).to be_empty
    end

    it "only allows 1 group in a long/traditional session" do
      picks = (1..4).map { |i| pick(exercise(name: "Ex #{i}")) }
      result = call(picks, fitness_level: "intermediate", goal: "gain_muscle", day_exercise_limit: 9)

      expect(result.groups.size).to eq(1)
      expect(result.leftovers.size).to eq(2)
    end
  end

  describe "advanced" do
    it "allows a circuit of up to 4 exercises" do
      picks = (1..4).map { |i| pick(exercise(name: "Ex #{i}"), sets: 3) }
      result = call(picks, fitness_level: "advanced", goal: "conditioning", day_exercise_limit: 9)

      expect(result.groups.size).to eq(1)
      expect(result.groups.first.members.size).to eq(4)
    end
  end

  describe "#call result shape" do
    it "sets rounds from the max sets among members and a sane rest_between_rounds_seconds default" do
      a = exercise(name: "A")
      b = exercise(name: "B")
      result = call([ pick(a, sets: 3, rest_seconds: 0), pick(b, sets: 4, rest_seconds: 0) ], fitness_level: "intermediate", goal: "gain_muscle")

      group = result.groups.first
      expect(group.rounds).to eq(4)
      expect(group.rest_between_rounds_seconds).to eq(90)
    end
  end
end
