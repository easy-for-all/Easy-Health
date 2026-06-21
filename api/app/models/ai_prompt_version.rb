class AiPromptVersion < ApplicationRecord
  has_many :ai_training_decision_logs, foreign_key: :prompt_version_id

  validates :name, :version, :prompt_type, :content, presence: true
  validates :name, uniqueness: { scope: :version }
  validates :prompt_type, inclusion: { in: %w[system user] }

  scope :active, -> { where(active: true) }

  def self.current_for(name)
    where(name: name, active: true).order(created_at: :desc).first
  end
end
