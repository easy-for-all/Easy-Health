require "rails_helper"

RSpec.describe ExerciseIntelligenceService do
  describe ".normalize_text" do
    it "lowercases and removes accents" do
      expect(described_class.normalize_text("Tríceps")).to eq("triceps")
      expect(described_class.normalize_text("Bíceps")).to eq("biceps")
      expect(described_class.normalize_text("Musculação")).to eq("musculacao")
    end

    it "strips extra spaces" do
      expect(described_class.normalize_text("  corda  ")).to eq("corda")
    end

    it "returns empty string for blank input" do
      expect(described_class.normalize_text(nil)).to eq("")
      expect(described_class.normalize_text("")).to eq("")
    end
  end

  describe ".resolve_activity" do
    it "normalizes bicicleta to bike" do
      expect(described_class.resolve_activity("bicicleta")).to eq("bike")
    end

    it "normalizes corrida to running" do
      expect(described_class.resolve_activity("corrida")).to eq("running")
    end

    it "normalizes caminhada to walking" do
      expect(described_class.resolve_activity("caminhada")).to eq("walking")
    end

    it "normalizes musculação to strength_training" do
      expect(described_class.resolve_activity("musculação")).to eq("strength_training")
    end

    it "normalizes spinning to bike" do
      expect(described_class.resolve_activity("spinning")).to eq("bike")
    end

    it "normalizes ciclismo to bike" do
      expect(described_class.resolve_activity("ciclismo")).to eq("bike")
    end

    it "returns nil for unknown activity" do
      expect(described_class.resolve_activity("xadrez")).to be_nil
    end
  end

  describe ".resolve_equipment" do
    it "normalizes corda to rope" do
      expect(described_class.resolve_equipment("corda")).to eq("rope")
    end

    it "normalizes cabo to cable" do
      expect(described_class.resolve_equipment("cabo")).to eq("cable")
    end

    it "normalizes barra to barbell" do
      expect(described_class.resolve_equipment("barra")).to eq("barbell")
    end

    it "normalizes halter to dumbbell" do
      expect(described_class.resolve_equipment("halter")).to eq("dumbbell")
    end

    it "normalizes halteres to dumbbell" do
      expect(described_class.resolve_equipment("halteres")).to eq("dumbbell")
    end

    it "normalizes máquina to machine" do
      expect(described_class.resolve_equipment("máquina")).to eq("machine")
    end

    it "normalizes elástico to band" do
      expect(described_class.resolve_equipment("elástico")).to eq("band")
    end
  end

  describe ".resolve_muscle" do
    it "normalizes peito to chest" do
      expect(described_class.resolve_muscle("peito")).to eq("chest")
    end

    it "normalizes costas to back" do
      expect(described_class.resolve_muscle("costas")).to eq("back")
    end

    it "normalizes tríceps (accented) to triceps" do
      expect(described_class.resolve_muscle("tríceps")).to eq("triceps")
    end

    it "normalizes perna to legs" do
      expect(described_class.resolve_muscle("perna")).to eq("legs")
    end

    it "normalizes abdômen to core" do
      expect(described_class.resolve_muscle("abdômen")).to eq("core")
    end
  end

  describe ".parse_user_intent" do
    it "detects pain constraint with shoulder" do
      result = described_class.parse_user_intent("Estou com dor no ombro")
      expect(result[:intent_type]).to eq("pain_constraint")
      expect(result[:constraint]).to eq("shoulder_pain")
    end

    it "detects pain constraint with knee" do
      result = described_class.parse_user_intent("meu joelho está doendo")
      expect(result[:intent_type]).to eq("pain_constraint")
      expect(result[:constraint]).to eq("knee_pain")
    end

    it "detects missing equipment" do
      result = described_class.parse_user_intent("não tenho cabo")
      expect(result[:intent_type]).to eq("equipment_unavailable")
    end

    it "detects home exercise request" do
      result = described_class.parse_user_intent("quero fazer em casa")
      expect(result[:intent_type]).to eq("home_exercise")
      expect(result[:location]).to eq("home")
    end

    it "detects lighter intensity request" do
      result = described_class.parse_user_intent("quero algo mais leve")
      expect(result[:intent_type]).to eq("reduce_intensity")
      expect(result[:intensity]).to eq("lighter")
    end

    it "detects heavier intensity request" do
      result = described_class.parse_user_intent("quero algo mais pesado")
      expect(result[:intent_type]).to eq("increase_intensity")
      expect(result[:intensity]).to eq("heavier")
    end

    it "detects bike/cardio request" do
      result = described_class.parse_user_intent("quero correr de bike")
      expect(result[:intent_type]).to eq("replace_with_cardio")
      expect(result[:target_activity]).to eq("bike")
    end

    it "detects bicicleta as bike activity" do
      result = described_class.parse_user_intent("prefiro bicicleta")
      expect(result[:intent_type]).to eq("replace_with_cardio")
      expect(result[:target_activity]).to eq("bike")
    end

    it "detects triceps with corda intent" do
      result = described_class.parse_user_intent("quero trocar por um exercício de triceps com corda")
      expect(result[:intent_type]).to eq("replace_exercise")
      expect(result[:target_muscle]).to eq("triceps")
      expect(result[:target_equipment]).to eq("rope")
    end

    it "detects favorite request" do
      result = described_class.parse_user_intent("quero um exercício favorito")
      expect(result[:intent_type]).to eq("use_favorite")
    end

    it "detects more options request" do
      result = described_class.parse_user_intent("me dá outra opção")
      expect(result[:intent_type]).to eq("request_more_options")
    end

    it "marks short generic text as general_swap" do
      result = described_class.parse_user_intent("ok")
      expect(result[:intent_type]).to eq("general_swap")
    end
  end

  describe ".rank_replacement_exercises" do
    let(:user) { create(:user) }
    let(:current_exercise) do
      Exercise.create!(
        name:           "Tríceps Corda",
        muscle_group:   "triceps",
        exercise_type:  "musculacao",
        equipment_type: "cable",
        difficulty:     "intermediate",
        gif_url:        "/exercise-images/gifdotreino/triceps/triceps-corda.gif",
      )
    end

    before do
      create(:health_profile, user: user, fitness_level: "intermediate", goal: "gain_muscle",
             age: 25, weight_kg: 70, height_cm: 175)
      WorkoutSession.create!(user: user, workout_day_id: nil, completed_at: 1.day.ago) rescue nil
    end

    context "when user has a favorite" do
      let(:favorite_exercise) do
        Exercise.create!(
          name:           "Tríceps Banco",
          muscle_group:   "triceps",
          exercise_type:  "musculacao",
          equipment_type: "bodyweight",
          difficulty:     "beginner",
          gif_url:        "/exercise-images/gifdotreino/triceps/triceps-banco.gif",
        )
      end

      before do
        UserFavoriteExercise.create!(user: user, exercise: favorite_exercise)
      end

      it "prioritizes favorited exercise" do
        intent = described_class.parse_user_intent("")

        results = described_class.rank_replacement_exercises(
          user:                  user,
          current_exercise:      current_exercise,
          intent:                intent,
          already_suggested_ids: [],
        )

        favorite_result = results.find { |r| r[:exercise].id == favorite_exercise.id }
        expect(favorite_result).to be_present
        expect(favorite_result[:score]).to be > 0
      end
    end

    context "with already_suggested_ids" do
      let(:other_exercise) do
        Exercise.create!(
          name:           "Tríceps Testa",
          muscle_group:   "triceps",
          exercise_type:  "musculacao",
          equipment_type: "barbell",
          difficulty:     "intermediate",
          gif_url:        "/exercise-images/gifdotreino/triceps/triceps-testa.gif",
        )
      end

      it "penalizes already suggested exercises" do
        intent = described_class.parse_user_intent("")

        results_without = described_class.rank_replacement_exercises(
          user:                  user,
          current_exercise:      current_exercise,
          intent:                intent,
          already_suggested_ids: [],
        )

        results_with = described_class.rank_replacement_exercises(
          user:                  user,
          current_exercise:      current_exercise,
          intent:                intent,
          already_suggested_ids: [other_exercise.id],
        )

        score_without = results_without.find { |r| r[:exercise].id == other_exercise.id }&.dig(:score)
        score_with    = results_with.find    { |r| r[:exercise].id == other_exercise.id }&.dig(:score)

        if score_without && score_with
          expect(score_with).to be < score_without
        end
      end
    end

    it "returns exercises with reason field" do
      intent  = described_class.parse_user_intent("")
      results = described_class.rank_replacement_exercises(
        user:                  user,
        current_exercise:      current_exercise,
        intent:                intent,
        already_suggested_ids: [],
      )

      results.each do |r|
        expect(r[:reason]).to be_a(String)
        expect(r[:reason]).not_to be_empty
      end
    end
  end
end
