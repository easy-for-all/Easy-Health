FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    transient do
      paid_plan { false }
    end

    trait :admin do
      admin { true }
    end

    after(:create) do |user, evaluator|
      if evaluator.paid_plan && user.subscription.blank?
        user.create_subscription!(status: "active", plan_name: "pro_monthly")
      end
    end
  end
end
