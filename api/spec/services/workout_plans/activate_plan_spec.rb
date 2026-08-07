require "rails_helper"

# Reprodução do incidente de produção: 52 usuários com dois workout_plans
# ativos, todos criados com segundos de diferença. A transação que já existia
# não bastava — ver o comentário de WorkoutPlans::ActivatePlan para o porquê.
RSpec.describe WorkoutPlans::ActivatePlan do
  def active_plans_for(user)
    WorkoutPlan.where(user_id: user.id, active: true)
  end

  describe "one active plan per owner" do
    it "leaves the user with exactly one active plan after repeated activations" do
      user = create(:user)
      owner = Workouts::UserOwner.new(user)

      3.times { described_class.call(owner: owner) }

      expect(WorkoutPlan.where(user_id: user.id).count).to eq(3)
      expect(active_plans_for(user).count).to eq(1)
    end

    it "activates the new plan and deactivates the previous one without deleting it" do
      user = create(:user)
      owner = Workouts::UserOwner.new(user)

      first  = described_class.call(owner: owner)
      second = described_class.call(owner: owner)

      expect(second.reload.active).to be(true)
      expect(first.reload.active).to be(false)
      expect(WorkoutPlan.exists?(first.id)).to be(true)
    end

    it "keeps the same invariant for an app installation" do
      installation = create(:app_installation, :anonymous)
      owner = Workouts::InstallationOwner.new(installation)

      described_class.call(owner: owner)
      second = described_class.call(owner: owner)

      active = WorkoutPlan.where(app_installation_id: installation.id, active: true)
      expect(active.count).to eq(1)
      expect(active.first.id).to eq(second.id)
    end

    it "does not touch plans that belong to another owner" do
      user  = create(:user)
      other = create(:user)
      other_plan = described_class.call(owner: Workouts::UserOwner.new(other))

      described_class.call(owner: Workouts::UserOwner.new(user))

      expect(other_plan.reload.active).to be(true)
    end
  end

  # O índice é a última proteção e precisa ser exercitado de verdade: um mock
  # aqui testaria a nossa opinião sobre o Postgres, não o Postgres. O INSERT é
  # cru justamente para passar por cima do model e bater no índice.
  describe "the database index itself" do
    it "rejects a second active plan for the same user" do
      user = create(:user)
      WorkoutPlan.create!(user: user, active: true)

      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO workout_plans (user_id, active, created_at, updated_at)
          VALUES (#{user.id}, true, NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a second active plan for the same installation" do
      installation = create(:app_installation, :anonymous)
      WorkoutPlan.create!(app_installation: installation, active: true)

      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO workout_plans (app_installation_id, active, created_at, updated_at)
          VALUES (#{installation.id}, true, NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "still allows a second INACTIVE plan for the same user" do
      user = create(:user)
      WorkoutPlan.create!(user: user, active: true)

      expect {
        WorkoutPlan.create!(user: user, active: false)
      }.to change { WorkoutPlan.where(user_id: user.id).count }.by(1)
    end
  end

  # Concorrência real, com threads e conexões separadas. Fixtures transacionais
  # ficam DESLIGADAS aqui de propósito: dentro de uma transação de teste as
  # outras threads não enxergariam as linhas criadas pela thread principal, e o
  # teste passaria por um motivo que não é o motivo certo.
  describe "concurrent activation", :concurrency do
    self.use_transactional_tests = false

    # destroy_all e não delete_all: sem transação de teste a limpeza é nossa, e
    # users tem dependentes com foreign key (public_profiles) que só as
    # cascatas do model removem. Antes e depois: uma execução interrompida no
    # meio deixaria lixo que faria o próximo run falhar por e-mail duplicado,
    # e não pelo motivo que o teste investiga.
    before do
      WorkoutPlan.delete_all
      AppInstallation.delete_all
      User.destroy_all
    end

    after do
      WorkoutPlan.delete_all
      AppInstallation.delete_all
      User.destroy_all
    end

    def activate_concurrently(count:, &owner_for_thread)
      latch  = Concurrent::CountDownLatch.new(1)
      errors = Concurrent::Array.new

      threads = Array.new(count) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            latch.wait(5)
            described_class.call(owner: owner_for_thread.call)
          rescue StandardError => e
            errors << e
          end
        end
      end

      latch.count_down
      threads.each { |t| t.join(20) }
      errors
    end

    it "never leaves two active plans for the same user" do
      user = create(:user)

      errors = activate_concurrently(count: 2) { Workouts::UserOwner.new(User.find(user.id)) }

      expect(errors).to be_empty
      expect(active_plans_for(user).count).to eq(1)
      # Os DOIS planos existem: as requisições foram serializadas, não
      # atropeladas. Sem o lock esta linha dá 1 — o índice recusa o segundo
      # INSERT e a request perdedora sai com o plano da outra. É esta contagem,
      # e não a de ativos, que distingue "protegido pelo lock" de "salvo pelo
      # índice no último instante".
      expect(WorkoutPlan.where(user_id: user.id).count).to eq(2)
    end

    it "never leaves two active plans for the same installation" do
      installation = create(:app_installation, :anonymous)

      errors = activate_concurrently(count: 2) do
        Workouts::InstallationOwner.new(AppInstallation.find(installation.id))
      end

      expect(errors).to be_empty
      expect(WorkoutPlan.where(app_installation_id: installation.id, active: true).count).to eq(1)
      expect(WorkoutPlan.where(app_installation_id: installation.id).count).to eq(2)
    end
  end

  # Se um dia surgir um caminho de escrita que não passe pelo lock, o índice
  # recusa e o serviço devolve o plano do vencedor em vez de um 500 genérico.
  describe "recovery when the index is the one that wins the race" do
    it "returns the owner's active plan and logs a structured event" do
      user = create(:user)
      owner = Workouts::UserOwner.new(user)
      winner = described_class.call(owner: owner)

      # Simula a corrida perdida: a criação estoura no índice, e o plano do
      # vencedor já está comitado e completo quando isso acontece.
      allow(WorkoutPlan).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))
      allow(Observability::Events).to receive(:workout_plan_activation_conflict)

      expect(described_class.call(owner: owner)).to eq(winner)
      expect(Observability::Events).to have_received(:workout_plan_activation_conflict)
        .with(hash_including(user_id: user.id, app_installation_id: nil, recovered: true))
      expect(active_plans_for(user).count).to eq(1)
    end

    it "raises instead of inventing a plan when there is nothing to recover" do
      user = create(:user)
      owner = Workouts::UserOwner.new(user)

      allow(WorkoutPlan).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

      expect { described_class.call(owner: owner) }
        .to raise_error(described_class::ActivationFailed)
    end
  end
end
