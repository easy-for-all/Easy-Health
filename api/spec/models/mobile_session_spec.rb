require "rails_helper"

RSpec.describe MobileSession, type: :model do
  let(:user) { create(:user) }

  describe ".issue_for!" do
    it "returns a prefixed raw token and stores only its digest" do
      token = described_class.issue_for!(user: user, platform: "ios")

      expect(token).to start_with(described_class::TOKEN_PREFIX)

      record = described_class.last
      expect(record.token_digest).to eq(Digest::SHA256.hexdigest(token))
      # The whole point of the digest: the raw token must not be recoverable
      # from the row.
      expect(described_class.where(token_digest: token)).to be_empty
    end

    it "issues distinct tokens for repeated calls" do
      first = described_class.issue_for!(user: user, platform: "ios")
      second = described_class.issue_for!(user: user, platform: "ios")

      expect(first).not_to eq(second)
    end

    it "persists the correlation metadata it was given" do
      described_class.issue_for!(
        user: user, platform: "ios",
        installation_id: "inst-123", app_version: "1.2.3"
      )

      expect(described_class.last).to have_attributes(
        installation_id: "inst-123", app_version: "1.2.3", platform: "ios"
      )
    end

    it "rejects a platform outside the allowlist" do
      expect { described_class.issue_for!(user: user, platform: "web") }
        .to raise_error(described_class::InvalidPlatformError)
    end
  end

  describe ".authenticate" do
    it "resolves a valid token to its session" do
      token = described_class.issue_for!(user: user, platform: "ios")

      expect(described_class.authenticate(token)&.user).to eq(user)
    end

    it "returns nil for an unknown token" do
      expect(described_class.authenticate("ehs_nope")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("   ")).to be_nil
    end

    it "returns nil once the session has expired" do
      token = described_class.issue_for!(user: user, platform: "ios")
      described_class.last.update_columns(expires_at: 1.second.ago)

      expect(described_class.authenticate(token)).to be_nil
    end

    it "returns nil once the session has been revoked" do
      token = described_class.issue_for!(user: user, platform: "ios")
      described_class.last.revoke!(reason: "user_signout")

      expect(described_class.authenticate(token)).to be_nil
    end

    it "returns nil when the account can no longer authenticate" do
      token = described_class.issue_for!(user: user, platform: "ios")
      user.update_columns(anonymized_at: Time.current)

      expect(described_class.authenticate(token)).to be_nil
    end

    it "stamps last_used_at on first use" do
      token = described_class.issue_for!(user: user, platform: "ios")

      expect { described_class.authenticate(token) }
        .to change { described_class.last.reload.last_used_at }.from(nil)
    end

    it "does not rewrite last_used_at within the throttle window" do
      token = described_class.issue_for!(user: user, platform: "ios")
      described_class.authenticate(token)
      first_seen = described_class.last.reload.last_used_at

      expect { described_class.authenticate(token) }
        .not_to change { described_class.last.reload.last_used_at }
      expect(first_seen).to be_present
    end
  end

  describe ".revoke_all_for!" do
    it "revokes every active session of that user and leaves others alone" do
      other_user = create(:user)
      mine = described_class.issue_for!(user: user, platform: "ios")
      theirs = described_class.issue_for!(user: other_user, platform: "ios")

      described_class.revoke_all_for!(user, reason: "account_deleted")

      expect(described_class.authenticate(mine)).to be_nil
      expect(described_class.authenticate(theirs)).to be_present
    end

    it "records why the session was revoked" do
      described_class.issue_for!(user: user, platform: "ios")

      described_class.revoke_all_for!(user, reason: "account_deleted")

      expect(described_class.last.revocation_reason).to eq("account_deleted")
    end
  end

  describe "validations" do
    it "rejects an unknown revocation reason" do
      session = build(:mobile_session, revoked_at: Time.current, revocation_reason: "because")

      expect(session).not_to be_valid
    end

    it "rejects a duplicate digest" do
      existing = create(:mobile_session)

      expect { create(:mobile_session, token_digest: existing.token_digest) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end

RSpec.describe MobileSession, "rotation and expiry policy", type: :model do
  let(:user) { create(:user) }

  describe "TTL" do
    it "defaults to 90 days" do
      described_class.issue_for!(user: user, platform: "ios")

      expect(described_class.last.expires_at).to be_within(1.minute).of(90.days.from_now)
    end

    it "is configurable" do
      with_env("MOBILE_SESSION_TTL_DAYS" => "7") do
        described_class.issue_for!(user: user, platform: "ios")
      end

      expect(described_class.last.expires_at).to be_within(1.minute).of(7.days.from_now)
    end

    it "falls back to the default for a nonsense value" do
      with_env("MOBILE_SESSION_TTL_DAYS" => "zero") do
        described_class.issue_for!(user: user, platform: "ios")
      end

      expect(described_class.last.expires_at).to be_within(1.minute).of(90.days.from_now)
    end
  end

  describe "re-login on the same device" do
    it "supersedes the previous session of that installation" do
      first = described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-1")
      second = described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-1")

      expect(described_class.authenticate(first)).to be_nil
      expect(described_class.authenticate(second)).to be_present
    end

    it "records why it was superseded" do
      described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-1")
      described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-1")

      superseded = described_class.where.not(revoked_at: nil).last
      expect(superseded.revocation_reason).to eq("superseded")
    end

    # Entrar no iPhone não pode deslogar o iPad.
    it "leaves other devices of the same user signed in" do
      iphone = described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-iphone")
      described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-ipad")
      described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-ipad")

      expect(described_class.authenticate(iphone)).to be_present
    end

    it "never touches another user's sessions" do
      other = create(:user)
      theirs = described_class.issue_for!(user: other, platform: "ios", installation_id: "inst-1")
      described_class.issue_for!(user: user, platform: "ios", installation_id: "inst-1")

      expect(described_class.authenticate(theirs)).to be_present
    end
  end

  describe "without an installation id" do
    it "caps how many active sessions a user can accumulate" do
      (described_class::MAX_ACTIVE_PER_USER + 4).times do
        described_class.issue_for!(user: user, platform: "ios")
      end

      expect(described_class.active.where(user_id: user.id).count)
        .to eq(described_class::MAX_ACTIVE_PER_USER)
    end

    it "keeps the most recent sessions" do
      newest = nil
      (described_class::MAX_ACTIVE_PER_USER + 2).times do
        newest = described_class.issue_for!(user: user, platform: "ios")
      end

      expect(described_class.authenticate(newest)).to be_present
    end
  end
end
