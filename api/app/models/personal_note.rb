class PersonalNote < ApplicationRecord
  belongs_to :personal, class_name: "User"
  belongs_to :client,   class_name: "User"

  validates :body, presence: true, length: { maximum: 2000 }
  validates :visibility, inclusion: { in: %w[private] }

  scope :for_client, ->(personal_id, client_id) {
    where(personal_id: personal_id, client_id: client_id).order(created_at: :desc)
  }
end
