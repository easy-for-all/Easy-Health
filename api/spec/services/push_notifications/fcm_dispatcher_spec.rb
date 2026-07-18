require "rails_helper"

RSpec.describe PushNotifications::FcmDispatcher do
  let(:user) { create(:user) }

  def sent_result(message_id: "mock/1")
    FirebasePushService::Result.new(status: "sent", message_id: message_id, invalid_token: false)
  end

  def dead_result(code: "UNREGISTERED")
    FirebasePushService::Result.new(status: "failed", error_code: code, invalid_token: true)
  end

  def temp_result(code: "http_500")
    FirebasePushService::Result.new(status: "failed", error_code: code, invalid_token: false)
  end

  def stub_fcm(*results)
    firebase = instance_double(FirebasePushService)
    allow(firebase).to receive(:deliver).and_return(*results)
    described_class.new(firebase: firebase)
  end

  it "sends to an active token and reports acceptance with the provider message id" do
    create(:device_token, user: user)
    dispatcher = stub_fcm(sent_result(message_id: "mock/abc"))

    result = dispatcher.call(user: user, title: "t", body: "b")

    expect(result.sent?).to be(true)
    expect(result.tokens_attempted).to eq(1)
    expect(result.tokens_accepted).to eq(1)
    expect(result.tokens_rejected).to eq(0)
    expect(result.provider_message_id).to eq("mock/abc")
  end

  it "returns an empty result when there is no active token" do
    dispatcher = stub_fcm(sent_result)
    result = dispatcher.call(user: user, title: "t", body: "b")

    expect(result.tokens_attempted).to eq(0)
    expect(result.sent?).to be(false)
  end

  it "invalidates a definitively-dead token (UNREGISTERED)" do
    device = create(:device_token, user: user)
    dispatcher = stub_fcm(dead_result)

    dispatcher.call(user: user, title: "t", body: "b")

    expect(device.reload.invalidated_at).to be_present
    expect(device.enabled).to be(false)
  end

  it "does NOT invalidate on a temporary failure (5xx/timeout)" do
    device = create(:device_token, user: user)
    dispatcher = stub_fcm(temp_result)

    result = dispatcher.call(user: user, title: "t", body: "b")

    expect(device.reload.invalidated_at).to be_nil
    expect(device.enabled).to be(true)
    expect(result.last_error_code).to eq("http_500")
  end

  it "stops at the first accepted token and does not touch the others" do
    create(:device_token, user: user)
    create(:device_token, user: user)
    firebase = instance_double(FirebasePushService)
    allow(firebase).to receive(:deliver).and_return(sent_result)

    result = described_class.new(firebase: firebase).call(user: user, title: "t", body: "b")

    expect(firebase).to have_received(:deliver).once
    expect(result.tokens_attempted).to eq(1)
    expect(result.tokens_accepted).to eq(1)
  end

  it "counts a rejection then an acceptance as a partial send" do
    create(:device_token, user: user)
    create(:device_token, user: user)
    dispatcher = stub_fcm(temp_result, sent_result)

    result = dispatcher.call(user: user, title: "t", body: "b")

    expect(result.tokens_attempted).to eq(2)
    expect(result.tokens_accepted).to eq(1)
    expect(result.tokens_rejected).to eq(1)
    expect(result.partial?).to be(true)
  end

  it "never logs a raw token" do
    device = create(:device_token, user: user, token: "supersecret-raw-token-value")
    logged = []
    allow(Rails.logger).to receive(:info) { |msg| logged << msg }
    dispatcher = stub_fcm(temp_result)

    dispatcher.call(user: user, title: "t", body: "b", correlation_id: "corr-1")

    expect(logged.join).not_to include("supersecret-raw-token-value")
    expect(logged.join).to include(device.masked_token)
  end
end
