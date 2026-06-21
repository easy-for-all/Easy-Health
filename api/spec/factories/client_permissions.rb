FactoryBot.define do
  factory :client_permission do
    association :personal_client_relationship
    can_view_adherence { true }
    can_view_assigned_workouts { true }
    can_view_completed_workouts { true }
    can_view_exercise_performance { false }
    can_view_body_weight { false }
    can_view_photos { false }
    can_view_body_analysis { false }
    can_view_exams { false }
  end
end
