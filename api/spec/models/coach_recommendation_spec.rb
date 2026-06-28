require "rails_helper"

RSpec.describe CoachRecommendation, type: :model do
  let(:user)     { create(:user) }
  let(:exercise) { Exercise.create!(name: "Supino Reto", muscle_group: "chest", exercise_type: "musculacao", equipment_type: "barbell", difficulty: "intermediate") }

  def build_rec(overrides = {})
    CoachRecommendation.new(
      {
        user:                user,
        exercise:            exercise,
        recommendation_type: "weight_progression",
        status:              "pending",
        title:               "Progressão sugerida",
        message:             "Aumente de 15kg para 17.5kg",
        exercise_name:       exercise.name,
        current_value:       15.0,
        recommended_value:   17.5,
        unit:                "kg",
        confidence:          0.85,
        reasons:             [ "Carga estável", "Séries concluídas" ]
      }.merge(overrides)
    )
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(build_rec).to be_valid
    end

    it "requires user" do
      expect(build_rec(user: nil)).not_to be_valid
    end

    it "requires recommendation_type" do
      expect(build_rec(recommendation_type: nil)).not_to be_valid
    end

    it "rejects unknown recommendation_type" do
      expect(build_rec(recommendation_type: "unknown_type")).not_to be_valid
    end

    it "requires status" do
      expect(build_rec(status: nil)).not_to be_valid
    end

    it "rejects unknown status" do
      expect(build_rec(status: "invalid_status")).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:pending_rec) do
      CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: user, exercise: exercise))
    end
    let!(:accepted_rec) do
      CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: user, exercise: exercise, status: "accepted", accepted_at: Time.current))
    end

    it "pending scope returns only pending records" do
      expect(CoachRecommendation.pending).to include(pending_rec)
      expect(CoachRecommendation.pending).not_to include(accepted_rec)
    end

    it "for_user scope filters by user" do
      other_user = create(:user)
      other_rec  = CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: other_user, exercise: exercise))

      expect(CoachRecommendation.for_user(user)).to include(pending_rec)
      expect(CoachRecommendation.for_user(user)).not_to include(other_rec)
    end
  end

  describe "#accept!" do
    it "sets status to accepted and records accepted_at" do
      rec = CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: user, exercise: exercise))

      expect { rec.accept! }.to change { rec.reload.status }.to("accepted")
      expect(rec.accepted_at).not_to be_nil
    end

    it "merges extra metadata" do
      rec = CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: user, exercise: exercise))
      rec.accept!(accepted_from: "home_coach_card")

      expect(rec.reload.metadata["accepted_from"]).to eq("home_coach_card")
    end
  end

  describe "#dismiss!" do
    it "sets status to dismissed and records dismissed_at" do
      rec = CoachRecommendation.create!(build_rec.attributes.symbolize_keys.merge(user: user, exercise: exercise))

      expect { rec.dismiss! }.to change { rec.reload.status }.to("dismissed")
      expect(rec.dismissed_at).not_to be_nil
    end
  end
end
