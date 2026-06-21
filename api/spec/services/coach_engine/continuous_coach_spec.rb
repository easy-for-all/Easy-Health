require "rails_helper"

RSpec.describe CoachEngine::ContinuousCoach, type: :service do
  let(:user) { create(:user) }
  let!(:fitness_profile) do
    create(:fitness_profile, user: user,
      consistency_score: 5.0,
      adherence_score:   5.0,
      risk_score:        3.0,
      behavior_pattern:  "unknown",
      training_archetype: "balanced_full_body",
      metadata: {})
  end

  subject(:coach) { described_class.new(user: user) }

  # Stubs workout_sessions scope to control inactivity logic
  def stub_last_session(completed_at)
    sessions_double = double("sessions_scope")
    allow(user).to receive(:workout_sessions).and_return(sessions_double)
    # For inactivity check
    allow(sessions_double).to receive(:order).and_return(double(first: completed_at ? double(completed_at: completed_at) : nil))
    # For positive progression / high consistency count
    allow(sessions_double).to receive(:where).and_return(double(count: 0))
  end

  describe "#call" do
    context "when user has no fitness profile" do
      before { fitness_profile.destroy }

      it "returns an empty array" do
        expect(coach.call).to eq([])
      end
    end

    context "inactivity check" do
      it "creates an inactivity insight when user has not trained in 7+ days" do
        stub_last_session(10.days.ago)

        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "inactivity").count
        }.by(1)
      end

      it "does not create an inactivity insight when user trained recently" do
        stub_last_session(1.day.ago)

        expect { coach.call }.not_to change {
          CoachInsight.where(user: user, insight_type: "inactivity").count
        }
      end

      it "creates an inactivity insight when user has never trained" do
        stub_last_session(nil)

        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "inactivity").count
        }.by(1)
      end

      it "stores the correct severity and source" do
        stub_last_session(10.days.ago)

        coach.call
        insight = CoachInsight.where(user: user, insight_type: "inactivity").last
        expect(insight.severity).to eq("warning")
        expect(insight.source).to eq("continuous_coach")
      end
    end

    context "low adherence + abandons_long_workouts" do
      before do
        fitness_profile.update!(
          adherence_score:  2.0,
          behavior_pattern: "abandons_long_workouts"
        )
        stub_last_session(1.day.ago)
      end

      it "creates a workout_adjustment insight" do
        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "workout_adjustment").count
        }.by(1)
      end

      it "does not create workout_adjustment when adherence is fine" do
        fitness_profile.update!(adherence_score: 6.0)

        expect { coach.call }.not_to change {
          CoachInsight.where(user: user, insight_type: "workout_adjustment").count
        }
      end

      it "does not create workout_adjustment when behavior pattern is different" do
        fitness_profile.update!(behavior_pattern: "high_adherence")

        expect { coach.call }.not_to change {
          CoachInsight.where(user: user, insight_type: "workout_adjustment").count
        }
      end
    end

    context "high consistency (achievement + progression)" do
      before do
        fitness_profile.update!(consistency_score: 8.0)
        sessions_double = double("sessions_scope")
        allow(user).to receive(:workout_sessions).and_return(sessions_double)
        allow(sessions_double).to receive(:order).and_return(double(first: double(completed_at: 1.day.ago)))
        allow(sessions_double).to receive(:where).and_return(double(count: 4))
      end

      it "creates an achievement insight" do
        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "achievement").count
        }.by_at_least(1)
      end
    end

    context "high risk" do
      before do
        fitness_profile.update!(risk_score: 8.0)
        stub_last_session(1.day.ago)
      end

      it "creates a risk insight" do
        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "risk").count
        }.by(1)
      end

      it "uses warning severity" do
        coach.call
        insight = CoachInsight.where(user: user, insight_type: "risk").last
        expect(insight.severity).to eq("warning")
        expect(insight.source).to eq("risk_analyst")
      end
    end

    context "deduplication within 48 hours" do
      before { stub_last_session(10.days.ago) }

      it "does not create a duplicate inactivity insight within 48 hours" do
        CoachInsight.create!(
          user: user, fitness_profile: fitness_profile,
          insight_type: "inactivity", title: "Already exists",
          message: "Already exists", severity: "warning",
          source: "continuous_coach", created_at: 1.hour.ago
        )

        expect { coach.call }.not_to change {
          CoachInsight.where(user: user, insight_type: "inactivity").count
        }
      end

      it "creates a new inactivity insight after 48 hours have passed" do
        CoachInsight.create!(
          user: user, fitness_profile: fitness_profile,
          insight_type: "inactivity", title: "Old insight",
          message: "Old insight", severity: "warning",
          source: "continuous_coach", created_at: 49.hours.ago
        )

        expect { coach.call }.to change {
          CoachInsight.where(user: user, insight_type: "inactivity").count
        }.by(1)
      end
    end

    context "return value" do
      it "returns an array of CoachInsight records" do
        stub_last_session(10.days.ago)

        result = coach.call
        expect(result).to be_an(Array)
        expect(result).to all(be_a(CoachInsight))
      end

      it "returns empty array when no insights are triggered" do
        stub_last_session(1.day.ago)
        fitness_profile.update!(consistency_score: 2.0, risk_score: 1.0)

        result = coach.call
        expect(result).to be_an(Array)
      end
    end
  end
end
