class ClientPermission < ApplicationRecord
  belongs_to :personal_client_relationship

  PERMISSION_KEYS = %w[
    can_view_assigned_workouts
    can_view_completed_workouts
    can_view_adherence
    can_view_exercise_performance
    can_view_body_weight
    can_view_photos
    can_view_body_analysis
    can_view_exams
  ].freeze

  def allowed?(key)
    public_send(key.to_s)
  end
end
