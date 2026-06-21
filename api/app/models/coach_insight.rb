class CoachInsight < ApplicationRecord
  belongs_to :user
  belongs_to :fitness_profile

  INSIGHT_TYPES = %w[
    adherence recovery progression risk motivation body_composition
    workout_adjustment inactivity achievement preference_learning archetype_adjustment
  ].freeze

  SEVERITIES = %w[info warning success].freeze
  SOURCES    = %w[continuous_coach behavior_analyst progress_analyst risk_analyst].freeze

  validates :insight_type, inclusion: { in: INSIGHT_TYPES }
  validates :severity,     inclusion: { in: SEVERITIES }
  validates :source,       inclusion: { in: SOURCES }
  validates :title, :message, presence: true

  scope :unread,   -> { where(read_at: nil) }
  scope :recent,   -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end
end
