require "rails_helper"

RSpec.describe HealthProfile, type: :model do
  describe "activity_preferences normalization" do
    let(:profile) { build(:health_profile) }

    it "normalizes bicicleta to cardio before validation" do
      profile.activity_preferences = ["bicicleta"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["cardio"])
    end

    it "normalizes eliptico to cardio before validation" do
      profile.activity_preferences = ["eliptico"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["cardio"])
    end

    it "normalizes escada to cardio before validation" do
      profile.activity_preferences = ["escada"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["cardio"])
    end

    it "normalizes remo to cardio before validation" do
      profile.activity_preferences = ["remo"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["cardio"])
    end

    it "normalizes mixed: musculacao + bicicleta -> musculacao + cardio" do
      profile.activity_preferences = ["musculacao", "bicicleta"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["musculacao", "cardio"])
    end

    it "keeps corrida as-is (valid activity type)" do
      profile.activity_preferences = ["corrida"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["corrida"])
    end

    it "keeps caminhada as-is (valid activity type)" do
      profile.activity_preferences = ["caminhada"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["caminhada"])
    end

    it "keeps hiit as-is (valid activity type)" do
      profile.activity_preferences = ["hiit"]
      profile.valid?
      expect(profile.activity_preferences).to eq(["hiit"])
    end
  end

  describe "activity_preferences validation" do
    let(:profile) { build(:health_profile) }

    it "is valid with empty activity_preferences" do
      profile.activity_preferences = []
      expect(profile).to be_valid
    end

    it "is valid with all known valid types" do
      HealthProfile::ACTIVITY_TYPES.each do |type|
        profile.activity_preferences = [type]
        expect(profile).to be_valid, "Expected #{type} to be valid"
      end
    end

    it "rejects completely unknown values even after normalization" do
      profile.activity_preferences = ["bicicleta_voadora"]
      expect(profile).not_to be_valid
      expect(profile.errors[:activity_preferences]).to include(
        a_string_matching("bicicleta_voadora")
      )
    end

    it "is valid after normalizing bicicleta (regression: no crash)" do
      profile.activity_preferences = ["bicicleta"]
      expect(profile).to be_valid
    end
  end

  describe "training preferences" do
    let(:profile) { build(:health_profile) }

    it "normalizes legacy locations and accepts expanded goals" do
      profile.training_location = "gym"
      profile.goal = "strength"

      expect(profile).to be_valid
      expect(profile.training_location).to eq("full_gym")
    end

    it "limits body focus to three structured values" do
      profile.preferred_body_focus = %w[glutes legs abs arms]

      expect(profile).not_to be_valid
      expect(profile.errors[:preferred_body_focus]).to include("permite no máximo 3 opções")
    end

    it "keeps none equipment exclusive" do
      profile.available_equipment = %w[none dumbbell]

      expect(profile).not_to be_valid
      expect(profile.errors[:available_equipment]).to include("'none' não pode ser combinado com outros equipamentos")
    end

    it "accepts one weekly session and supported preference values" do
      profile.training_days_per_week = 1
      profile.session_duration_minutes = 25
      profile.intensity_preference = "easy_start"
      profile.training_context = "pregnant"

      expect(profile).to be_valid
    end
  end
end
