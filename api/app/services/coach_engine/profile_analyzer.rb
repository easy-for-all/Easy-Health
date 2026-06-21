module CoachEngine
  class ProfileAnalyzer
    VERSION = "v1".freeze

    def initialize(user:, fitness_profile:, health_profile: nil)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
    end

    def call(source: "automatic")
      results = analyze
      apply!(results, source: source)
      results
    end

    private

    def analyze
      {
        "persona" => PersonaClassifier.new(user: @user, fitness_profile: @fitness_profile, health_profile: @health_profile).call,
        "training_archetype" => TrainingArchetypeClassifier.new(user: @user, fitness_profile: @fitness_profile, health_profile: @health_profile).call,
        "behavior" => BehaviorAnalyst.new(user: @user, fitness_profile: @fitness_profile, health_profile: @health_profile).call,
        "progress" => ProgressAnalyst.new(user: @user, fitness_profile: @fitness_profile, health_profile: @health_profile).call,
        "risk" => RiskAnalyst.new(user: @user, fitness_profile: @fitness_profile, health_profile: @health_profile).call
      }
    end

    def apply!(results, source:)
      persona = results.fetch("persona")
      archetype = results.fetch("training_archetype")
      behavior = results.fetch("behavior")
      risk = results.fetch("risk")
      changes = classification_changes(persona, archetype, behavior)

      @fitness_profile.update!(
        primary_persona: persona.fetch("primary_persona"),
        secondary_persona: persona.fetch("secondary_persona"),
        training_archetype: archetype.fetch("training_archetype"),
        secondary_training_archetype: archetype.fetch("secondary_training_archetype"),
        behavior_pattern: behavior.fetch("behavior_pattern"),
        risk_score: [ @fitness_profile.risk_score.to_f, risk.fetch("risk_score").to_f ].max.round(2),
        classification_version: "v2",
        metadata: @fitness_profile.metadata.merge("coach_engine" => audit_metadata(results, source))
      )

      track_changes(changes)
      @fitness_profile
    end

    def classification_changes(persona, archetype, behavior)
      {
        persona: @fitness_profile.primary_persona != persona.fetch("primary_persona") ||
          @fitness_profile.secondary_persona != persona.fetch("secondary_persona"),
        archetype: @fitness_profile.training_archetype != archetype.fetch("training_archetype") ||
          @fitness_profile.secondary_training_archetype != archetype.fetch("secondary_training_archetype"),
        behavior: @fitness_profile.behavior_pattern != behavior.fetch("behavior_pattern")
      }
    end

    def audit_metadata(results, source)
      {
        "version" => VERSION,
        "analyzed_at" => Time.current.iso8601,
        "source" => source.to_s,
        "persona" => results.fetch("persona"),
        "training_archetype" => results.fetch("training_archetype"),
        "behavior" => results.fetch("behavior"),
        "progress" => results.fetch("progress"),
        "risk" => results.fetch("risk")
      }
    end

    def track_changes(changes)
      track(:persona_classified) if changes[:persona]
      track(:training_archetype_classified) if changes[:archetype]
      track(:behavior_pattern_updated) if changes[:behavior]
    end

    def track(event)
      UserEventService.track(
        user: @user,
        event: event,
        metadata: {
          fitness_profile_id: @fitness_profile.id,
          version: VERSION
        }
      )
    end
  end
end
