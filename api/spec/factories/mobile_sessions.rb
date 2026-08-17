FactoryBot.define do
  factory :mobile_session do
    user
    platform { "ios" }
    sequence(:token_digest) { |n| Digest::SHA256.hexdigest("mobile-session-token-#{n}") }
    expires_at { 90.days.from_now }

    trait :android do
      platform { "android" }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :revoked do
      revoked_at { 1.hour.ago }
      revocation_reason { "user_signout" }
    end
  end
end
