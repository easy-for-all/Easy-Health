class PersonalClientRelationship < ApplicationRecord
  STATUSES = %w[invited active paused removed].freeze
  INVITATION_TTL = 72.hours

  belongs_to :personal, class_name: "User"
  belongs_to :client, class_name: "User", optional: true
  has_one :client_permission, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :invitation_code, presence: true, uniqueness: true

  after_create :create_default_permissions

  scope :active, -> { where(status: "active") }
  scope :invited, -> { where(status: "invited") }

  def invitation_expired?
    invitation_expires_at.present? && invitation_expires_at <= Time.current
  end

  def activate!
    update!(status: "active", started_at: Time.current)
  end

  private

  def create_default_permissions
    create_client_permission!(
      can_view_assigned_workouts:    true,
      can_view_completed_workouts:   true,
      can_view_adherence:            true,
      can_view_exercise_performance: false,
      can_view_body_weight:          false,
      can_view_photos:               false,
      can_view_body_analysis:        false,
      can_view_exams:                false
    )
  end
end
