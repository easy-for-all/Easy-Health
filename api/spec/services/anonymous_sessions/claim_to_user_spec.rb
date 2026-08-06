require "rails_helper"

RSpec.describe AnonymousSessions::ClaimToUser do
  let(:user) { create(:user) }
  let(:installation) do
    AppInstallation.create!(installation_id: "claim-1", platform: "android", native: true, app_build: "60")
  end
  let(:session) do
    AnonymousOnboardingSession.create!(
      app_installation: installation,
      profile_answers: {
        "goal" => "gain_muscle", "training_days_per_week" => 4,
        "age" => 30, "weight_kg" => 80, "height_cm" => 175, "fitness_level" => "beginner"
      }
    )
  end

  def anonymous_plan
    WorkoutPlan.create!(app_installation: installation, active: true)
  end

  def anonymous_session_record
    WorkoutSession.create!(
      app_installation: installation, status: "completed",
      completed_at: Time.current, duration_minutes: 40
    )
  end

  it "moves plans and sessions to the user" do
    plan = anonymous_plan
    workout = anonymous_session_record

    result = described_class.new(user: user, session: session).call

    expect(result).to be_claimed
    expect(result.plans_claimed).to eq(1)
    expect(result.sessions_claimed).to eq(1)

    expect(plan.reload.user_id).to eq(user.id)
    expect(plan.app_installation_id).to be_nil
    expect(workout.reload.user_id).to eq(user.id)
    expect(session.reload.claimed_by_user_id).to eq(user.id)
  end

  it "writes the wizard answers into a real health profile" do
    described_class.new(user: user, session: session).call

    profile = user.reload.health_profile
    expect(profile).to be_present
    expect(profile.goal).to eq("gain_muscle")
    expect(profile.training_days_per_week).to eq(4)
  end

  # A pessoa pode já ter perfil (veio pela Web antes). O merge é assimétrico de
  # propósito: as respostas do wizard são as MAIS RECENTES e ganham nos campos
  # em comum, mas um campo que o wizard não perguntou não pode ser apagado.
  it "merges into an existing profile instead of replacing it" do
    user.create_health_profile!(
      goal: "lose_weight", height_cm: 180, age: 40, weight_kg: 90,
      fitness_level: "intermediate", session_duration_minutes: 45
    )

    described_class.new(user: user, session: session).call

    profile = user.reload.health_profile
    expect(profile.goal).to eq("gain_muscle")
    expect(profile.height_cm).to eq(175)
    expect(profile.session_duration_minutes).to eq(45)
  end

  # O índice parcial "um plano ativo por usuário" estouraria no meio da
  # transação se o plano anterior do usuário não fosse desativado antes.
  it "deactivates the user's own plan before moving the anonymous one" do
    existing = WorkoutPlan.create!(user: user, active: true)
    anonymous_plan

    expect { described_class.new(user: user, session: session).call }.not_to raise_error

    expect(existing.reload.active).to be(false)
    expect(user.workout_plans.where(active: true).count).to eq(1)
  end

  # RateLimiter conta AiUsageLog do dia por usuário com teto 3. Trazer as
  # gerações anônimas junto faria a pessoa chegar à conta nova já bloqueada —
  # exatamente quem o fluxo quer ativar.
  it "leaves the AI cost logs with the installation" do
    usage = AiUsageLog.create!(app_installation: installation, task_type: "workout_planning", model: "x")
    decision = AiTrainingDecisionLog.create!(
      app_installation: installation, workout_plan: anonymous_plan,
      generation_type: "workout_plan", status: "success"
    )

    described_class.new(user: user, session: session).call

    expect(usage.reload.user_id).to be_nil
    expect(decision.reload.user_id).to be_nil
    expect(AiUsageLog.where(user_id: user.id).count).to eq(0)
  end

  it "keeps the plan even when the answers do not make a valid profile" do
    session.update!(profile_answers: { "goal" => "gain_muscle" })
    plan = anonymous_plan

    result = described_class.new(user: user, session: session).call

    expect(result).to be_claimed
    expect(result.profile_claimed).to be(false)
    expect(plan.reload.user_id).to eq(user.id)
    expect(user.reload.health_profile).to be_nil
  end

  it "is idempotent for the same user" do
    anonymous_plan
    described_class.new(user: user, session: session).call

    result = described_class.new(user: user.reload, session: session.reload).call

    expect(result.status).to eq(:already_claimed)
    expect(result.plans_claimed).to eq(0)
  end

  it "refuses to hand the data to a second user" do
    anonymous_plan
    described_class.new(user: user, session: session).call
    intruder = create(:user)

    result = described_class.new(user: intruder, session: session.reload).call

    expect(result.status).to eq(:conflict)
    expect(result).to be_permanent
    expect(session.reload.claimed_by_user_id).to eq(user.id)
    expect(intruder.workout_plans.count).to eq(0)
  end

  # Uma resposta de posse, não duas: se o aparelho já é de outra conta, os dados
  # dele não podem passar para uma terceira.
  it "stops when the installation belongs to another account" do
    installation.update_columns(user_id: create(:user).id)
    anonymous_plan

    result = described_class.new(user: user, session: session).call

    expect(result.status).to eq(:conflict)
    expect(result.failure_code).to eq("user_conflict")
    expect(session.reload.last_claim_failure_code).to eq("user_conflict")
    expect(user.workout_plans.count).to eq(0)
  end

  it "never raises to the caller" do
    allow(WorkoutPlan).to receive(:where).and_raise(StandardError, "db down")

    result = described_class.new(user: user, session: session).call

    expect(result.status).to eq(:unexpected_error)
    expect(result.success).to be(false)
  end

  it "reports invalid input instead of blowing up on a nil session" do
    result = described_class.new(user: user, session: nil).call

    expect(result.status).to eq(:invalid_input)
  end
end
