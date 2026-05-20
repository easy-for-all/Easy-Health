module AiAgents
  class BaseAgentService
    SESSIONS_TO_ANALYZE = 15

    def initialize(user)
      @user = user
    end

    private

    def recent_sessions
      @recent_sessions ||= @user.workout_sessions
        .order(completed_at: :desc)
        .limit(SESSIONS_TO_ANALYZE)
    end

    def call_claude(prompt, task_key = :agent_analysis)
      client = Anthropic::Client.new(access_token: ENV.fetch("ANTHROPIC_API_KEY"))
      cfg = AiConfig.for(task_key)

      response = client.messages(parameters: {
        model:      cfg[:model],
        max_tokens: cfg[:max_tokens],
        messages: [{ role: "user", content: prompt }]
      })

      response.dig("content", 0, "text").to_s.strip
    rescue KeyError => e
      Rails.logger.error("[AiAgent] ANTHROPIC_API_KEY not set: #{e.message}")
      nil
    rescue => e
      Rails.logger.error("[AiAgent] error: #{e.message}")
      nil
    end

    def sessions_summary_text
      sessions = recent_sessions
      return "Nenhuma sessão de treino registrada ainda." if sessions.empty?

      lines = sessions.map do |s|
        date = s.completed_at.strftime("%d/%m/%Y")
        logs = (s.exercise_logs || []).map do |log|
          weights = Array(log["weight_by_set"] || [log["weight_kg"]].compact)
          reps    = Array(log["reps"])
          "#{log['name']}: #{weights.join('/')} kg × #{reps.join('/')} reps (#{log['sets'] || 0} séries)"
        end.join("; ")
        "#{date} | #{s.duration_minutes} min | #{logs}"
      end

      lines.join("\n")
    end

    def exercise_progression
      exercise_map = {}
      recent_sessions.each do |s|
        (s.exercise_logs || []).each do |log|
          name = log["name"]
          next if name.blank?
          weights = Array(log["weight_by_set"] || [log["weight_kg"]].compact).map(&:to_f).reject(&:zero?)
          avg_weight = weights.any? ? weights.sum / weights.size : 0
          sets_done  = (log["sets"] || 0).to_i
          sets_plan  = (log["planned_sets"] || sets_done).to_i

          exercise_map[name] ||= []
          exercise_map[name] << {
            date:       s.completed_at.strftime("%d/%m"),
            avg_weight: avg_weight,
            sets_done:  sets_done,
            sets_plan:  sets_plan
          }
        end
      end
      exercise_map
    end
  end
end
