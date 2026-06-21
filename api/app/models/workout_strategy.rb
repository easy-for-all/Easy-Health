class WorkoutStrategy < ApplicationRecord
  VERSION = "v1".freeze

  belongs_to :user
  belongs_to :workout_plan
  belongs_to :fitness_profile, optional: true

  validates :strategy_version, presence: true
  validates :strategy, presence: true
end
