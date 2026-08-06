module Workouts
  # O dono anônimo. Todo campo derivado de histórico responde vazio POR
  # CONSTRUÇÃO, e não por acaso: uma instalação sem conta não tem passado, e
  # inventar um "último peso" para ela seria inventar dado.
  class InstallationOwner
    attr_reader :installation

    def initialize(installation)
      @installation = installation
    end

    def user = nil
    def anonymous? = true
    def plans = WorkoutPlan.where(app_installation_id: @installation.id)
    def sessions = WorkoutSession.where(app_installation_id: @installation.id)
    def plan_attributes = { app_installation_id: @installation.id }
    def log_attributes = { app_installation_id: @installation.id }

    # As respostas do wizard viram uma HealthProfile NÃO PERSISTIDA. O gerador
    # só lê o perfil; criar uma linha órfã em health_profiles só para satisfazer
    # uma leitura deixaria lixo que o claim depois teria que reconciliar.
    def health_profile
      answers = @installation.anonymous_onboarding_session&.profile_answers
      return nil if answers.blank?

      HealthProfile.new(answers.slice(*self.class.profile_attribute_names))
    end

    def favorite_exercise_ids(_exercise_ids) = Set.new
    def all_favorite_exercise_ids = []
    def active_plan = plans.find_by(active: true)

    # Sem conta não há trial nem assinatura. O teto diário de IA cai no
    # gratuito, que é o mesmo teto de quem acabou de se cadastrar.
    def paid_access? = false

    def history_for(exercise_id:, block_type:) = NullHistory.new

    # As colunas que o wizard pode preencher. Derivado do schema em vez de uma
    # lista fixa: uma coluna nova de perfil passa a atravessar o fluxo anônimo
    # sem que ninguém precise lembrar de acrescentá-la aqui.
    def self.profile_attribute_names
      @profile_attribute_names ||= HealthProfile.column_names - %w[id user_id created_at updated_at]
    end
  end
end
