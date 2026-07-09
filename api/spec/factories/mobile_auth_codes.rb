FactoryBot.define do
  factory :mobile_auth_code do
    user
    platform { "android" }
    expires_at { 5.minutes.from_now }
    used_at { nil }

    transient do
      code { SecureRandom.urlsafe_base64(32) }
    end

    code_digest { MobileAuthCode.digest(code) }
  end
end
