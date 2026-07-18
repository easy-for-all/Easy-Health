FactoryBot.define do
  factory :device_token do
    user
    sequence(:token) { |n| "tok-#{n}-#{SecureRandom.hex(6)}" }
    platform { "android" }
    enabled { true }
    permission_status { "granted" }
  end
end
