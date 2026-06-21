FactoryBot.define do
  factory :community_post do
    association :user
    post_type { "workout_completed" }
    title { "Treino concluído" }
    visibility { "public" }
    metadata { { duration_minutes: 45 } }
  end
end
