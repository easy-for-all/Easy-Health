FactoryBot.define do
  factory :relationship_message do
    association :user
    event_name  { "user_created" }
    journey_key { "onboarding" }
    step_key    { "welcome_email" }
    channel     { "email" }
    provider    { "brevo" }
    template_key { "EH_001_WELCOME" }
    status      { "sent" }
    sent_at     { Time.current }

    trait :failed do
      status        { "failed" }
      sent_at       { nil }
      failed_at     { Time.current }
      error_message { "Brevo API error" }
    end

    trait :skipped do
      status     { "skipped" }
      sent_at    { nil }
      skipped_at { Time.current }
    end

    trait :with_idempotency_key do
      sequence(:idempotency_key) { |n| "make:exec#{n}:welcome_email:#{user_id}" }
    end
  end
end
