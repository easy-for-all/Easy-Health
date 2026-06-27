require "rails_helper"

RSpec.describe WorkoutSession, type: :model do
  let(:user) { create(:user) }

  def valid_attrs(overrides = {})
    {
      completed_at:    Time.current,
      duration_minutes: 45
    }.merge(overrides)
  end

  describe "validations" do
    it "is valid with default completion_status" do
      session = user.workout_sessions.build(valid_attrs)
      expect(session).to be_valid
    end

    it "accepts completion_status: completed" do
      session = user.workout_sessions.build(valid_attrs(completion_status: "completed"))
      expect(session).to be_valid
    end

    it "accepts completion_status: completed_partial" do
      session = user.workout_sessions.build(valid_attrs(completion_status: "completed_partial"))
      expect(session).to be_valid
    end

    it "accepts completion_status: abandoned" do
      session = user.workout_sessions.build(valid_attrs(completion_status: "abandoned"))
      expect(session).to be_valid
    end

    it "rejects unknown completion_status" do
      session = user.workout_sessions.build(valid_attrs(completion_status: "unknown"))
      expect(session).not_to be_valid
      expect(session.errors[:completion_status]).to be_present
    end

    it "accepts nil completion_status" do
      session = user.workout_sessions.build(valid_attrs(completion_status: nil))
      expect(session).to be_valid
    end

    it "accepts completion_rate between 0 and 100" do
      session = user.workout_sessions.build(valid_attrs(completion_rate: 75.5))
      expect(session).to be_valid
    end

    it "rejects completion_rate above 100" do
      session = user.workout_sessions.build(valid_attrs(completion_rate: 101))
      expect(session).not_to be_valid
    end

    it "rejects negative completion_rate" do
      session = user.workout_sessions.build(valid_attrs(completion_rate: -1))
      expect(session).not_to be_valid
    end

    it "accepts nil completion_rate" do
      session = user.workout_sessions.build(valid_attrs(completion_rate: nil))
      expect(session).to be_valid
    end

    it "requires duration_minutes > 0" do
      session = user.workout_sessions.build(valid_attrs(duration_minutes: 0))
      expect(session).not_to be_valid
    end
  end

  describe "skipped_exercises" do
    it "stores and retrieves skipped_exercises as JSONB" do
      skipped = [ { "exercise_id" => 1, "name" => "Supino", "planned_sets" => 3 } ]
      session = user.workout_sessions.create!(valid_attrs(skipped_exercises: skipped))
      expect(session.reload.skipped_exercises).to eq(skipped)
    end

    it "defaults skipped_exercises to nil when not provided" do
      session = user.workout_sessions.create!(valid_attrs)
      expect([ nil, [] ]).to include(session.skipped_exercises)
    end
  end

  describe "extra_block fields" do
    it "stores extra_block_type and extra_block_data" do
      extra_data = { "modality" => "bike", "duration_minutes" => 20, "intensity" => "moderate" }
      session = user.workout_sessions.create!(
        valid_attrs(
          extra_block_type: "cardio",
          extra_block_data: extra_data,
          extra_started_at: 1.hour.ago,
          extra_completed_at: 40.minutes.ago
        )
      )
      reloaded = session.reload
      expect(reloaded.extra_block_type).to eq("cardio")
      expect(reloaded.extra_block_data["modality"]).to eq("bike")
      expect(reloaded.extra_started_at).to be_present
      expect(reloaded.extra_completed_at).to be_present
    end
  end
end
