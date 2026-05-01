class WorkoutPlan < ApplicationRecord
  belongs_to :user
  has_many :workout_days, dependent: :destroy

  scope :active, -> { where(active: true) }
end
