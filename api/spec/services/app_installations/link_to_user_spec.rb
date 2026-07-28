require "rails_helper"

RSpec.describe AppInstallations::LinkToUser do
  let(:user) { create(:user) }

  def link(installation:, user:, **kwargs)
    described_class.call(installation: installation, user: user, **kwargs)
  end

  describe "a new link" do
    let(:installation) { create(:app_installation, :anonymous) }

    it "links the user and stamps the whole attempt bookkeeping" do
      result = link(installation: installation, user: user, source: "reconciliation")

      expect(result.success).to be(true)
      expect(result.status).to eq(:linked)
      expect(result.failure_code).to be_nil

      installation.reload
      expect(installation.user_id).to eq(user.id)
      expect(installation.linked_at).to be_present
      expect(installation.first_link_attempt_at).to be_present
      expect(installation.last_link_attempt_at).to be_present
      expect(installation.link_attempts_count).to eq(1)
      expect(installation.last_authenticated_at).to be_present
    end

    it "clears a previous failure code on success" do
      installation.update_columns(last_link_failure_code: "user_conflict")

      link(installation: installation, user: user)

      expect(installation.reload.last_link_failure_code).to be_nil
    end

    it "records runtime_context when given" do
      link(installation: installation, user: user, runtime_context: "android_native")

      expect(installation.reload.runtime_context).to eq("android_native")
    end

    it "leaves runtime_context untouched when not given" do
      installation.update_columns(runtime_context: "android_native")

      link(installation: installation, user: user)

      expect(installation.reload.runtime_context).to eq("android_native")
    end
  end

  describe "idempotency" do
    let(:installation) { create(:app_installation, user: user, last_authenticated_at: Time.current) }

    it "is a no-op for an installation already linked to the same user" do
      installation.update_columns(linked_at: 3.days.ago, link_attempts_count: 1)
      linked_at = installation.reload.linked_at

      result = link(installation: installation, user: user)

      expect(result.success).to be(true)
      expect(result.status).to eq(:already_linked)

      installation.reload
      expect(installation.linked_at).to be_within(1.second).of(linked_at)
      expect(installation.link_attempts_count).to eq(1)
      expect(installation.first_link_attempt_at).to be_nil
    end

    it "never moves linked_at once it is set" do
      link(installation: create(:app_installation, :anonymous), user: user)
      installation = AppInstallation.linked.last
      original = installation.linked_at

      3.times { link(installation: installation.reload, user: user) }

      expect(installation.reload.linked_at).to be_within(1.second).of(original)
    end

    it "refreshes last_authenticated_at only once per TOUCH_INTERVAL" do
      installation.update_columns(last_authenticated_at: 5.minutes.ago)
      recent = installation.reload.last_authenticated_at

      link(installation: installation, user: user)
      expect(installation.reload.last_authenticated_at).to be_within(1.second).of(recent)

      installation.update_columns(last_authenticated_at: 2.hours.ago)
      link(installation: installation.reload, user: user)
      expect(installation.reload.last_authenticated_at).to be_within(5.seconds).of(Time.current)
    end
  end

  describe "conflict" do
    let(:owner) { create(:user) }
    let(:installation) { create(:app_installation, user: owner, last_authenticated_at: 1.day.ago) }

    it "never steals an installation owned by another user" do
      result = link(installation: installation, user: user)

      expect(result.success).to be(false)
      expect(result.status).to eq(:conflict)
      expect(result.failure_code).to eq("user_conflict")

      installation.reload
      expect(installation.user_id).to eq(owner.id)
      expect(installation.last_link_failure_code).to eq("user_conflict")
      expect(installation.link_attempts_count).to eq(1)
      expect(installation.first_link_attempt_at).to be_present
      expect(installation.linked_at).to be_nil
    end
  end

  describe "invalid input" do
    it "returns invalid_input for a nil installation, without raising" do
      result = link(installation: nil, user: user)

      expect(result.success).to be(false)
      expect(result.status).to eq(:invalid_input)
    end

    it "returns invalid_input for a nil user" do
      installation = create(:app_installation, :anonymous)

      result = link(installation: installation, user: nil)

      expect(result.status).to eq(:invalid_input)
      expect(installation.reload.link_attempts_count).to eq(0)
    end

    it "returns invalid_input for an unpersisted installation" do
      result = link(installation: build(:app_installation), user: user)

      expect(result.status).to eq(:invalid_input)
    end
  end

  describe "failures" do
    let(:installation) { create(:app_installation, :anonymous) }

    it "returns validation_failed and still records the attempt" do
      allow(installation).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(installation))

      result = link(installation: installation, user: user)

      expect(result.success).to be(false)
      expect(result.status).to eq(:validation_failed)
      expect(result.failure_code).to eq("validation_failed")

      installation.reload
      expect(installation.user_id).to be_nil
      expect(installation.link_attempts_count).to eq(1)
      expect(installation.last_link_failure_code).to eq("validation_failed")
    end

    it "returns unexpected_error and reports it, without raising to the caller" do
      allow(installation).to receive(:with_lock).and_raise(StandardError, "boom")

      expect { @result = link(installation: installation, user: user) }.not_to raise_error
      expect(@result.status).to eq(:unexpected_error)
      expect(installation.reload.last_link_failure_code).to eq("unexpected_error")
    end
  end

  describe "logging" do
    let(:installation) { create(:app_installation, :anonymous) }

    it "hashes the installation_id and never logs it raw" do
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      link(installation: installation, user: user, source: "reconciliation")

      payload = logged.find { |line| line.include?("installation_link_succeeded") }
      expect(payload).to be_present
      expect(payload).not_to include(installation.installation_id)
      expect(JSON.parse(payload)["installation_id_hash"].length).to eq(12)
      expect(JSON.parse(payload)["user_id"]).to eq(user.id)
    end

    # The caller emits Observability::Events under the SAME event names for the
    # same link, and both reach the log sink. Without producer, counting
    # installation_link_succeeded in the logs would double-count one link.
    it "tags its own lines with a producer so they can be told apart" do
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }

      link(installation: installation, user: user)

      payload = JSON.parse(logged.find { |line| line.include?("installation_link_succeeded") })
      expect(payload["producer"]).to eq(described_class::PRODUCER)
    end

    it "keeps failure_code inside the closed vocabulary" do
      logged = []
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      owner = create(:user)
      owned = create(:app_installation, user: owner)

      link(installation: owned, user: user)

      payload = JSON.parse(logged.find { |line| line.include?("installation_link_conflict") })
      expect(described_class::FAILURE_CODES).to include(payload["failure_code"])
      expect(owned.reload.last_link_failure_code).to be_in(described_class::FAILURE_CODES)
    end

    it "never logs a success for an already-linked installation" do
      linked_install = create(:app_installation, user: user, last_authenticated_at: 5.minutes.ago)
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }

      expect(link(installation: linked_install, user: user).status).to eq(:already_linked)
      expect(logged.grep(/installation_link_succeeded/)).to be_empty
    end
  end

  describe "build independence" do
    # build_number exists here only to prove there is NO condition on it: the
    # Android shell loads a remote web bundle, so an old shell sends the same
    # header as a new one.
    it "links identically across old and new build numbers" do
      old_build = create(:app_installation, :anonymous, app_build: "34")
      new_build = create(:app_installation, :anonymous, app_build: "47")

      old_result = link(installation: old_build, user: user, build_number: "34")
      new_result = link(installation: new_build, user: create(:user), build_number: "47")

      expect(old_result.status).to eq(:linked)
      expect(new_result.status).to eq(:linked)
      expect(old_build.reload.user_id).to eq(user.id)
    end
  end

  describe "concurrency", :concurrent do
    # Real threads need real connections, so the surrounding transaction has to go.
    self.use_transactional_tests = false

    # destroy_all, not delete_all: users own dependent rows behind foreign keys.
    after do
      AppInstallation.delete_all
      User.where(id: @created_user_ids).destroy_all
    end

    # Without the surrounding transaction, factory sequences can collide with
    # rows a previous run left behind, so the email is made unique explicitly.
    def make_user
      user = create(:user, email: "link-race-#{SecureRandom.uuid}@example.com")
      (@created_user_ids ||= []) << user.id
      user
    end

    def race(installation_id, users)
      users.map do |u|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(
              installation: AppInstallation.find(installation_id),
              user: u,
              source: "concurrency-spec"
            )
          end
        end
      end.map(&:value)
    end

    it "produces one link and one already_linked for the same user" do
      subject_user = make_user
      installation = create(:app_installation, :anonymous)

      statuses = race(installation.id, [ subject_user, subject_user ]).map(&:status)

      expect(statuses).to contain_exactly(:linked, :already_linked)
      installation.reload
      expect(installation.user_id).to eq(subject_user.id)
      expect(installation.link_attempts_count).to eq(1)
    end

    it "lets only the first link win for different users" do
      first = make_user
      second = make_user
      installation = create(:app_installation, :anonymous)

      results = race(installation.id, [ first, second ])
      statuses = results.map(&:status)

      expect(statuses).to contain_exactly(:linked, :conflict)
      installation.reload
      expect([ first.id, second.id ]).to include(installation.user_id)
      expect(installation.last_link_failure_code).to eq("user_conflict")
      expect(installation.link_attempts_count).to eq(2)
    end
  end
end
