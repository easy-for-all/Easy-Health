class UserBadge < ApplicationRecord
  belongs_to :user

  BADGE_DEFINITIONS = [
    { key: "first_workout",   icon: "💪", name: "Primeiro Treino",    desc: "Complete seu primeiro treino",       condition: ->(u) { u.workout_sessions.any? }                              },
    { key: "streak_3",        icon: "🔥", name: "3 dias seguidos",    desc: "Treine 3 dias consecutivos",         condition: ->(u) { current_streak(u) >= 3 }                               },
    { key: "streak_7",        icon: "⚡", name: "7 dias seguidos",    desc: "Treine 7 dias consecutivos",         condition: ->(u) { current_streak(u) >= 7 }                               },
    { key: "streak_30",       icon: "🏅", name: "30 dias seguidos",   desc: "Treine 30 dias consecutivos",        condition: ->(u) { current_streak(u) >= 30 }                              },
    { key: "workouts_10",     icon: "🥈", name: "10 Treinos",         desc: "Complete 10 treinos no total",       condition: ->(u) { u.workout_sessions.count >= 10 }                       },
    { key: "workouts_50",     icon: "🥇", name: "50 Treinos",         desc: "Complete 50 treinos no total",       condition: ->(u) { u.workout_sessions.count >= 50 }                       },
    { key: "workouts_100",    icon: "🏆", name: "100 Treinos",        desc: "Complete 100 treinos no total",      condition: ->(u) { u.workout_sessions.count >= 100 }                      },
    { key: "consistency",     icon: "🎯", name: "Consistente",        desc: "Treine pelo menos 4x por semana",    condition: ->(u) { weekly_frequency(u) >= 4 }                             },
    { key: "community",       icon: "🌍", name: "Comunidade",         desc: "Ative seu perfil na comunidade",    condition: ->(u) { u.community_enabled? }                                 },
    { key: "early_bird",      icon: "🌅", name: "Madrugador",         desc: "Treine antes das 8h",               condition: ->(u) { early_workout?(u) }                                    },
  ].freeze

  def self.current_streak(user)
    sessions = user.workout_sessions
      .where("completed_at > ?", 60.days.ago)
      .order(completed_at: :desc)
      .pluck(:completed_at)

    return 0 if sessions.empty?

    streak = 0
    last_date = nil
    sessions.map { |t| t.to_date }.uniq.each do |date|
      if last_date.nil? || last_date - date == 1
        streak += 1
        last_date = date
      else
        break
      end
    end
    streak
  end

  def self.weekly_frequency(user)
    user.workout_sessions
      .where("completed_at > ?", 7.days.ago)
      .count
  end

  def self.early_workout?(user)
    user.workout_sessions
      .where("EXTRACT(HOUR FROM completed_at) < 8")
      .any?
  end

  def self.sync_for(user)
    BADGE_DEFINITIONS.each do |defn|
      next if where(user: user, badge_key: defn[:key]).exists?
      create!(user: user, badge_key: defn[:key]) if defn[:condition].call(user)
    end
  end
end
