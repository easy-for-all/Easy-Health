class AiUsageLog < ApplicationRecord
  belongs_to :user

  scope :today,    -> { where(created_at: Date.current.all_day) }
  scope :for_task, ->(t) { where(task_type: t.to_s) }
end
