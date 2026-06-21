class UserEvent < ApplicationRecord
  belongs_to :user

  validates :event_name, presence: true

  self.record_timestamps = false
end
