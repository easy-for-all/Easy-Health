require "rails_helper"

# Unit spec for the Google Ads REST transport. The network is always mocked at
# #http_post — the real round-trip is validated separately against the Google
# Ads UI (see docs/google-ads-android-acquisition.md), never with a mock.
RSpec.describe GoogleAds::Client do
  FakeAdsResponse = Struct.new(:code, :body, :headers) do
    def [](key)
      (headers || {})[key]
    end
  end

  CREDENTIALS = {
    "GOOGLE_ADS_DEVELOPER_TOKEN" => "dev-token",
    "GOOGLE_ADS_CLIENT_ID" => "client-id",
    "GOOGLE_ADS_CLIENT_SECRET" => "client-secret",
    "GOOGLE_ADS_REFRESH_TOKEN" => "refresh-token",
    "GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH" => "123-456-7890",
    "GOOGLE_ADS_CUSTOMER_ID" => nil,
    "GOOGLE_ADS_LOGIN_CUSTOMER_ID" => nil
  }.freeze

  def with_credentials(overrides = {}, &block)
    with_env(CREDENTIALS.merge(overrides), &block)
  end

  # Captures every (uri, headers, body) triple the client would put on the wire
  # and replays the given responses in order.
  def stub_transport(client, responses)
    calls = []
    # Not Array(): FakeAdsResponse is a Struct, and Array(struct) would splat it
    # into its own members instead of wrapping it.
    queue = responses.is_a?(Array) ? responses.dup : [ responses ]

    last = nil
    allow(client).to receive(:http_post) do |uri, headers, body|
      calls << { uri: uri, headers: headers, body: JSON.parse(body) }
      # The final response repeats once the queue runs out, so a "keeps
      # failing" scenario can be expressed with a single response.
      last = queue.shift || last
    end

    calls
  end

  def ok_response(body)
    FakeAdsResponse.new("200", JSON.generate(body), {})
  end

  before do
    allow(described_class).to receive(:access_token).and_return("access-token")
  end

  describe ".configured?" do
    it "is false when any required credential is missing" do
      with_credentials("GOOGLE_ADS_REFRESH_TOKEN" => nil) do
        expect(described_class.configured?).to be(false)
        expect(described_class.missing_env).to include("GOOGLE_ADS_REFRESH_TOKEN")
      end
    end

    it "is true when every credential and the customer id are present" do
      with_credentials { expect(described_class.configured?).to be(true) }
    end
  end

  describe "API version" do
    it "targets v25 and never an older version" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(client, ok_response({ "results" => [] }))

        client.search("SELECT campaign.id FROM campaign")

        expect(described_class::API_VERSION).to eq("v25")
        expect(calls.first[:uri].to_s).to include("/v25/")
        expect(calls.first[:uri].to_s).not_to include("/v21/")
      end
    end
  end

  describe "customer id normalization" do
    it "sends only digits even when the env carries hyphens" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(client, ok_response({ "results" => [] }))

        client.search("SELECT campaign.id FROM campaign")

        expect(calls.first[:uri].to_s).to include("/customers/1234567890/googleAds:search")
      end
    end
  end

  describe "login-customer-id (MCC opcional)" do
    it "omits the header when no manager account is configured" do
      with_credentials("GOOGLE_ADS_LOGIN_CUSTOMER_ID" => nil) do
        client = described_class.new
        calls = stub_transport(client, ok_response({ "results" => [] }))

        client.search("SELECT campaign.id FROM campaign")

        expect(calls.first[:headers]).not_to have_key("login-customer-id")
      end
    end

    it "sends the header stripped of hyphens when it is configured" do
      with_credentials("GOOGLE_ADS_LOGIN_CUSTOMER_ID" => "123-456-7890") do
        client = described_class.new
        calls = stub_transport(client, ok_response({ "results" => [] }))

        client.search("SELECT campaign.id FROM campaign")

        expect(calls.first[:headers]["login-customer-id"]).to eq("1234567890")
      end
    end
  end

  describe "pagination" do
    it "follows nextPageToken and aggregates every page exactly once" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(client, [
          ok_response({ "results" => [ { "campaign" => { "id" => "1" } } ], "nextPageToken" => "page-2" }),
          ok_response({ "results" => [ { "campaign" => { "id" => "2" } } ] })
        ])

        rows = client.search("SELECT campaign.id FROM campaign")

        expect(rows.map { |row| row.dig("campaign", "id") }).to eq(%w[1 2])
        expect(calls.size).to eq(2)
        expect(calls.first[:body]).not_to have_key("pageToken")
        expect(calls.last[:body]["pageToken"]).to eq("page-2")
      end
    end
  end

  describe "retry" do
    before { allow_any_instance_of(described_class).to receive(:sleep) }

    it "retries a transient 503 and then succeeds" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(client, [
          FakeAdsResponse.new("503", JSON.generate({ "error" => { "message" => "unavailable" } }), {}),
          ok_response({ "results" => [ { "campaign" => { "id" => "1" } } ] })
        ])

        rows = client.search("SELECT campaign.id FROM campaign")

        expect(rows.size).to eq(1)
        expect(calls.size).to eq(2)
      end
    end

    it "does not retry a 401 — an authentication fault must surface immediately" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(
          client,
          FakeAdsResponse.new("401", JSON.generate({ "error" => { "message" => "invalid grant" } }),
                              { "request-id" => "req-401" })
        )

        expect { client.search("SELECT campaign.id FROM campaign") }
          .to raise_error(GoogleAds::Client::Error, /status=401/)
        expect(calls.size).to eq(1)
      end
    end

    it "gives up after MAX_RETRIES on a persistent transient error" do
      with_credentials do
        client = described_class.new
        calls = stub_transport(client, FakeAdsResponse.new("429", "{}", {}))

        expect { client.search("SELECT campaign.id FROM campaign") }
          .to raise_error(GoogleAds::Client::Error, /status=429/)
        expect(calls.size).to eq(described_class::MAX_RETRIES + 1)
      end
    end
  end

  describe "error reporting" do
    it "carries Google's request-id and never any credential" do
      with_credentials do
        client = described_class.new
        stub_transport(
          client,
          FakeAdsResponse.new("400", JSON.generate({ "error" => { "message" => "bad query" } }),
                              { "request-id" => "req-abc123" })
        )

        error = nil
        begin
          client.search("SELECT nope FROM campaign")
        rescue GoogleAds::Client::Error => e
          error = e
        end

        expect(error.request_id).to eq("req-abc123")
        expect(error.message).to include("request_id=req-abc123")
        expect(error.message).not_to include("dev-token")
        expect(error.message).not_to include("refresh-token")
        expect(error.message).not_to include("access-token")
        expect(error.message).not_to include("client-secret")
      end
    end
  end

  describe "missing credentials" do
    it "raises NotConfiguredError instead of attempting a request" do
      with_credentials("GOOGLE_ADS_DEVELOPER_TOKEN" => nil) do
        expect { described_class.new.search("SELECT campaign.id FROM campaign") }
          .to raise_error(GoogleAds::Client::NotConfiguredError)
      end
    end
  end
end
