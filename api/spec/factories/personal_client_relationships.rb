FactoryBot.define do
  factory :personal_client_relationship do
    association :personal, factory: :user
    association :client, factory: :user
    invitation_code { SecureRandom.hex(8) }
    status { "active" }
    started_at { Time.current }

    trait :invited do
      status { "invited" }
      client { nil }
      started_at { nil }
    end
  end
end
