FactoryBot.define do
  factory :app_installation do
    sequence(:installation_id) { |n| "inst-#{n}-#{SecureRandom.uuid}" }
    platform { "android" }
    native { true }
    app_version { "1.0.0" }
    app_build { "42" }
    source { "register" }
    first_seen_at { Time.current }
    tracking_started_at { Time.current }
    last_seen_at { Time.current }

    trait :anonymous do
      user { nil }
    end

    trait :authenticated do
      user
      last_authenticated_at { Time.current }
    end
  end
end
