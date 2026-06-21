module CoachEngine
  class TrainingArchetypeClassifier
    CARDIO_ACTIVITIES = %w[cardio corrida caminhada natacao hiit].freeze
    LOWER_MUSCLE_GROUPS = %w[legs glutes calves].freeze
    UPPER_MUSCLE_GROUPS = %w[chest back shoulders biceps triceps forearms trapezius].freeze
    MINIMUM_BODY_FOCUS_SIGNALS = 3
    DOMINANCE_THRESHOLD = 0.6

    def initialize(user:, fitness_profile:, health_profile: nil)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
    end

    def call
      primary = classified_archetype
      secondary = secondary_archetype(primary)
      {
        "training_archetype" => primary,
        "secondary_training_archetype" => secondary,
        "confidence" => confidence,
        "explanation" => explanation_for(primary),
        "evidence" => {
          "activity_preferences" => Array(@health_profile&.activity_preferences),
          "body_focus_signal_count" => body_focus_signal_count,
          "dominant_body_focus" => dominant_body_focus
        }
      }
    end

    private

    def classified_archetype
      return "balanced_full_body" unless @health_profile

      activities = Array(@health_profile.activity_preferences)
      return "cardio_focused" if activities.any? && (activities - CARDIO_ACTIVITIES).empty?
      return "functional_fitness" if activities == [ "funcional" ]

      case dominant_body_focus
      when "glutes" then "glute_focused"
      when "lower" then "lower_body_focused"
      when "upper" then "upper_body_focused"
      else goal_archetype
      end
    end

    def goal_archetype
      {
        "gain_muscle" => "aesthetic_hypertrophy",
        "body_definition" => "aesthetic_hypertrophy",
        "lose_weight" => "weight_loss",
        "health" => "health_and_longevity",
        "health_longevity" => "health_and_longevity",
        "strength" => "strength_focused",
        "conditioning" => "athletic_performance",
        "mobility" => "mobility_focused",
        "safe_return" => "rehabilitation",
        "maintain" => "balanced_full_body"
      }.fetch(@health_profile.goal, "balanced_full_body")
    end

    def secondary_archetype(primary)
      return "lower_body_focused" if primary == "glute_focused"
      return "weight_loss" if primary == "cardio_focused" && @health_profile&.goal == "lose_weight"

      nil
    end

    def body_focus_signal_count
      muscle_group_counts.values.sum
    end

    def dominant_body_focus
      counts = muscle_group_counts
      return nil if counts.values.sum < MINIMUM_BODY_FOCUS_SIGNALS

      group, count = counts.max_by { |_, value| value }
      return nil unless count.to_f / counts.values.sum >= DOMINANCE_THRESHOLD

      case group
      when "glutes" then "glutes"
      when *LOWER_MUSCLE_GROUPS then "lower"
      when *UPPER_MUSCLE_GROUPS then "upper"
      end
    end

    def muscle_group_counts
      @muscle_group_counts ||= begin
        ids = @user.favorite_exercises.pluck(:id) + completed_exercise_ids
        exercises = Exercise.where(id: ids.uniq).pluck(:id, :muscle_group).to_h
        counts = Hash.new(0)

        @user.favorite_exercises.pluck(:id).each { |id| counts[exercises[id]] += 1 if exercises[id].present? }
        completed_exercise_ids.each { |id| counts[exercises[id]] += 1 if exercises[id].present? }
        declared_body_focus_groups.each { |group| counts[group] += 1 }
        counts
      end
    end

    def declared_body_focus_groups
      Array(@health_profile&.preferred_body_focus).filter_map do |focus|
        {
          "glutes" => "glutes",
          "legs" => "legs",
          "abs" => "core",
          "arms" => "biceps",
          "chest" => "chest",
          "back" => "back",
          "shoulders" => "shoulders"
        }[focus]
      end
    end

    def completed_exercise_ids
      @completed_exercise_ids ||= @user.workout_sessions.where(completed_at: 90.days.ago..).pluck(:exercise_logs).flat_map do |logs|
        Array(logs).filter_map { |log| exercise_id = log["exercise_id"].to_i; exercise_id if exercise_id.positive? }
      end
    end

    def confidence
      value = 0.35
      value += 0.25 if Array(@health_profile&.activity_preferences).any?
      value += 0.25 if body_focus_signal_count >= MINIMUM_BODY_FOCUS_SIGNALS
      value += 0.15 if @health_profile&.goal.present?
      value.clamp(0, 0.95).round(2)
    end

    def explanation_for(archetype)
      {
        "glute_focused" => "Favoritos e execuções mostram foco consistente em glúteos.",
        "lower_body_focused" => "Favoritos e execuções mostram foco consistente em membros inferiores.",
        "upper_body_focused" => "Favoritos e execuções mostram foco consistente em membros superiores.",
        "cardio_focused" => "As atividades declaradas são predominantemente cardiovasculares.",
        "functional_fitness" => "A preferência declarada é por treino funcional.",
        "aesthetic_hypertrophy" => "O objetivo atual favorece hipertrofia com foco em simetria.",
        "weight_loss" => "O objetivo atual pede uma estratégia de redução de peso com aderência.",
        "strength_focused" => "O objetivo atual prioriza evolução de força com progressão técnica.",
        "athletic_performance" => "O objetivo atual favorece condicionamento e desempenho progressivos.",
        "mobility_focused" => "O objetivo atual prioriza mobilidade e movimentos controlados.",
        "rehabilitation" => "O retorno seguro pede uma abordagem gradual e conservadora.",
        "health_and_longevity" => "O objetivo atual favorece saúde geral e longevidade.",
        "balanced_full_body" => "Ainda não há sinais suficientes para um foco corporal mais específico."
      }.fetch(archetype)
    end
  end
end
