class ExerciseSuggestionLog < ApplicationRecord
  belongs_to :user
  belongs_to :current_exercise,   class_name: "Exercise", foreign_key: :current_exercise_id,   optional: true
  belongs_to :suggested_exercise, class_name: "Exercise", foreign_key: :suggested_exercise_id, optional: true

  EVENT_TYPES = %w[suggestion_shown suggestion_accepted suggestion_rejected suggestion_skipped
                   asked_more_options search_used favorite_filter_used].freeze

  validates :event_type, inclusion: { in: EVENT_TYPES }

  scope :accepted,   -> { where(accepted: true) }
  scope :today,      -> { where(created_at: Date.current.all_day) }
  scope :for_user,   ->(u) { where(user: u) }
end
