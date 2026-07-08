require "rails_helper"

# Unit tests for the admin controller helper methods.
# HTTP-level auth tests require DatabaseCleaner or similar setup (see CLAUDE.md)
# and can be verified manually: see spec description below.
#
# Manual verification:
#   1. Login as admin in the app at /admin
#   2. Confirm no email column appears in the user list
#   3. Confirm EH-XXXXXX IDs appear in the user list
#   4. Click "Ver" on a user and confirm email appears in the modal
#   5. GET /api/v1/admin/users as non-admin → 403
#   6. Confirm GET /api/v1/admin/stats includes onboarding_analytics.activation_funnel
#      and recent_activation_events with masked user names (no full email)
RSpec.describe Api::V1::AdminController do
  let(:controller_instance) { described_class.new }

  def admin_display_id(user)
    controller_instance.send(:admin_display_id, user)
  end

  def display_name(user)
    controller_instance.send(:display_name, user)
  end

  def relative_time_label(time)
    controller_instance.send(:relative_time_label, time)
  end

  def engagement_score(sessions_count, plans_count, sessions)
    controller_instance.send(:engagement_score, sessions_count, plans_count, sessions)
  end

  describe "#admin_display_id" do
    it "formats as EH- with 6-digit zero-padded id" do
      user = instance_double(User, id: 193)
      expect(admin_display_id(user)).to eq("EH-000193")
    end

    it "handles single-digit ids" do
      user = instance_double(User, id: 1)
      expect(admin_display_id(user)).to eq("EH-000001")
    end

    it "handles 7-digit ids without truncation" do
      user = instance_double(User, id: 1_000_000)
      expect(admin_display_id(user)).to eq("EH-1000000")
    end
  end

  describe "#display_name" do
    it "shows first name and last initial for full name" do
      user = instance_double(User, id: 1, name: "Marcus Reis")
      expect(display_name(user)).to eq("Marcus R.")
    end

    it "shows just first name when user has only one name" do
      user = instance_double(User, id: 2, name: "Madonna")
      expect(display_name(user)).to eq("Madonna")
    end

    it "falls back to Usuário EH-XXXXXX when name is blank" do
      user = instance_double(User, id: 42, name: "")
      expect(display_name(user)).to eq("Usuário EH-000042")
    end

    it "falls back to Usuário EH-XXXXXX when name is nil" do
      user = instance_double(User, id: 5, name: nil)
      expect(display_name(user)).to eq("Usuário EH-000005")
    end

    it "handles name with multiple words correctly" do
      user = instance_double(User, id: 3, name: "João Carlos Silva")
      expect(display_name(user)).to eq("João S.")
    end
  end

  describe "#relative_time_label" do
    it "returns 'Agora' for times within the last hour" do
      expect(relative_time_label(30.minutes.ago)).to eq("Agora")
    end

    it "returns 'Há 1 hora' for ~1 hour ago" do
      expect(relative_time_label(70.minutes.ago)).to eq("Há 1 hora")
    end

    it "returns 'Há X horas' for times within 24 hours" do
      expect(relative_time_label(5.hours.ago)).to eq("Há 5 horas")
    end

    it "returns 'Ontem' for times between 24h and 48h ago" do
      expect(relative_time_label(30.hours.ago)).to eq("Ontem")
    end

    it "returns 'Há X dias' for times within 7 days" do
      expect(relative_time_label(4.days.ago)).to eq("Há 4 dias")
    end

    it "returns a formatted date for older times" do
      time = 10.days.ago
      expect(relative_time_label(time)).to eq(time.strftime("%d/%m/%Y"))
    end
  end

  describe "#engagement_score" do
    let(:no_sessions) { [] }

    it "returns 'low' when no sessions and no plans" do
      expect(engagement_score(0, 0, no_sessions)).to eq("low")
    end

    it "returns 'medium' when there is at least 1 session" do
      session = instance_double(WorkoutSession, completed_at: 2.days.ago)
      expect(engagement_score(1, 0, [session])).to eq("medium")
    end

    it "returns 'medium' when there is a plan but no sessions" do
      expect(engagement_score(0, 1, no_sessions)).to eq("medium")
    end

    it "returns 'high' for 3+ sessions" do
      sessions = 3.times.map { instance_double(WorkoutSession, completed_at: 2.days.ago) }
      expect(engagement_score(3, 0, sessions)).to eq("high")
    end

    it "returns 'high' when active on 3+ different days in last 7 days" do
      sessions = [1, 2, 3].map { |d| instance_double(WorkoutSession, completed_at: d.days.ago) }
      expect(engagement_score(3, 0, sessions)).to eq("high")
    end

    it "returns 'medium' for 2 sessions (not yet high)" do
      sessions = 2.times.map { instance_double(WorkoutSession, completed_at: 2.days.ago) }
      expect(engagement_score(2, 0, sessions)).to eq("medium")
    end
  end

  describe "#activation_event_row" do
    def activation_event_row(event)
      controller_instance.send(:activation_event_row, event)
    end

    it "masks the user via display_name and summarizes metadata" do
      user = instance_double(User, id: 7, name: "Marcus Reis")
      event = instance_double(
        OnboardingEvent,
        user: user,
        event_name: "activation_start_clicked",
        occurred_at: Time.zone.parse("2026-07-01 10:00:00"),
        created_at: Time.zone.parse("2026-07-01 09:59:00"),
        metadata: { "workout_plan_id" => 55, "workout_session_id" => nil, "exercise_id" => nil }
      )

      row = activation_event_row(event)

      expect(row[:user_display_name]).to eq("Marcus R.")
      expect(row[:event_name]).to eq("activation_start_clicked")
      expect(row[:workout_plan_id]).to eq(55)
      expect(row[:metadata_summary]).to eq({ "workout_plan_id" => 55, "workout_session_id" => nil, "exercise_id" => nil })
      expect(row).not_to have_key(:email)
    end

    it "resolves workout_plan_id from a nested workout hash (UserEvent-shaped metadata)" do
      user = instance_double(User, id: 8, name: "Ana Souza")
      event = instance_double(
        UserEvent,
        user: user,
        event_name: "activation_workout_created",
        occurred_at: nil,
        created_at: Time.zone.parse("2026-07-02 08:00:00"),
        metadata: { "workout" => { "id" => 99 } }
      )

      row = activation_event_row(event)

      expect(row[:occurred_at]).to eq(Time.zone.parse("2026-07-02 08:00:00").iso8601)
      expect(row[:workout_plan_id]).to eq(99)
    end
  end
end
