require "rails_helper"

# Estes testes protegem invariantes de BANCO, não de modelo. Eles existem porque
# tornar workout_plans.user_id anulável desarma silenciosamente o índice único
# que garantia "um plano ativo por dono": no Postgres, dois NULLs são distintos,
# então sem os índices parciais TODA linha anônima escaparia da restrição — sem
# erro, sem log, sem ninguém notando até alguém ver dois planos ativos.
RSpec.describe "WorkoutPlan ownership invariants", type: :model do
  let(:user) { create(:user) }
  let(:installation) { AppInstallation.create!(installation_id: "own-1", platform: "android", native: true) }
  let(:other_installation) { AppInstallation.create!(installation_id: "own-2", platform: "android", native: true) }

  describe "exactly one owner" do
    it "accepts a user-owned plan" do
      expect(WorkoutPlan.new(user: user, active: true)).to be_valid
    end

    it "accepts an installation-owned plan" do
      expect(WorkoutPlan.new(app_installation: installation, active: true)).to be_valid
    end

    it "rejects a plan with no owner" do
      expect(WorkoutPlan.new(active: true)).not_to be_valid
    end

    it "rejects a plan with two owners" do
      expect(WorkoutPlan.new(user: user, app_installation: installation, active: true)).not_to be_valid
    end

    # O CHECK é a última linha de defesa: uma escrita que contorne as validações
    # (update_all, import, console) ainda tem que ser recusada.
    it "is enforced by the database even when validations are bypassed" do
      plan = WorkoutPlan.create!(user: user, active: true)

      expect {
        WorkoutPlan.where(id: plan.id).update_all(app_installation_id: installation.id)
      }.to raise_error(ActiveRecord::StatementInvalid, /workout_plans_single_owner/)
    end
  end

  describe "one active plan per owner" do
    it "still restricts users" do
      WorkoutPlan.create!(user: user, active: true)

      expect {
        WorkoutPlan.create!(user: user, active: true)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # O teste que justifica a migration: sem o índice parcial por instalação,
    # esta criação passaria e o dono anônimo acumularia planos ativos.
    it "restricts installations too" do
      WorkoutPlan.create!(app_installation: installation, active: true)

      expect {
        WorkoutPlan.create!(app_installation: installation, active: true)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "does not restrict across different installations" do
      WorkoutPlan.create!(app_installation: installation, active: true)

      expect {
        WorkoutPlan.create!(app_installation: other_installation, active: true)
      }.not_to raise_error
    end

    it "allows many inactive plans per owner" do
      2.times { WorkoutPlan.create!(app_installation: installation, active: false) }

      expect(WorkoutPlan.owned_by_installation(installation).count).to eq(2)
    end
  end

  describe "WorkoutSession" do
    it "rejects a session with two owners" do
      session = WorkoutSession.new(user: user, app_installation: installation, status: "in_progress")
      expect(session).not_to be_valid
    end

    # Comunidade e recalibração de perfil são coisas de conta; disparar os
    # callbacks para uma sessão anônima daria NoMethodError em nil, não um post
    # sem autor.
    it "skips the account-only callbacks for an anonymous session" do
      expect(RecalibrateFitnessProfileJob).not_to receive(:perform_later)

      expect {
        WorkoutSession.create!(
          app_installation: installation, status: "completed",
          completed_at: Time.current, duration_minutes: 30
        )
      }.not_to change(CommunityPost, :count)
    end
  end
end
