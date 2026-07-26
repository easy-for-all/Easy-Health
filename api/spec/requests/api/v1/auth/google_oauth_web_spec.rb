require "rails_helper"

# The web Google flow used to start with `redirect("/users/auth/google_oauth2")`
# straight from routes.rb, which drops the query string — so the consent flags
# never reached OmniAuth and no new Google account could be created on the web.
# These specs exercise the real redirect, not a stub of it.
RSpec.describe "GET /auth/google/web", type: :request do
  def location_params
    query = URI.parse(response.headers["Location"]).query
    Rack::Utils.parse_nested_query(query.to_s)
  end

  def location_path
    URI.parse(response.headers["Location"]).path
  end

  it "redirects to the OmniAuth request phase" do
    get "/auth/google/web"

    expect(response).to have_http_status(:found)
    expect(location_path).to eq("/users/auth/google_oauth2")
  end

  it "never invents consent when none was sent" do
    get "/auth/google/web"

    expect(location_params).to eq(
      "terms_accepted" => "false",
      "privacy_accepted" => "false",
      "marketing_consent" => "false"
    )
  end

  it "preserves the three allowed consent params" do
    get "/auth/google/web", params: { terms_accepted: "1", privacy_accepted: "1", marketing_consent: "1" }

    expect(location_params).to eq(
      "terms_accepted" => "true",
      "privacy_accepted" => "true",
      "marketing_consent" => "true"
    )
  end

  it "keeps falsy values falsy" do
    get "/auth/google/web", params: { terms_accepted: "1", privacy_accepted: "1", marketing_consent: "0" }

    expect(location_params["marketing_consent"]).to eq("false")
  end

  it "treats non-affirmative values as a refusal instead of coercing them" do
    get "/auth/google/web", params: { terms_accepted: "yes", privacy_accepted: "on" }

    expect(location_params["terms_accepted"]).to eq("false")
    expect(location_params["privacy_accepted"]).to eq("false")
  end

  it "drops unknown params" do
    get "/auth/google/web", params: { terms_accepted: "1", privacy_accepted: "1", utm_source: "campaign", admin: "1" }

    expect(location_params.keys).to match_array(%w[terms_accepted privacy_accepted marketing_consent])
  end

  it "does not become an open redirect" do
    get "/auth/google/web", params: {
      redirect_url: "https://evil.example.com",
      return_to: "https://evil.example.com",
      host: "evil.example.com",
      origin: "https://evil.example.com"
    }

    location = URI.parse(response.headers["Location"])
    expect(location.host).to be_nil.or eq("www.example.com")
    expect(location.path).to eq("/users/auth/google_oauth2")
    expect(response.headers["Location"]).not_to include("evil.example.com")
  end

  it "accepts POST the same way (the route is mounted for both verbs)" do
    post "/auth/google/web", params: { terms_accepted: "1", privacy_accepted: "1" }

    expect(response).to have_http_status(:found)
    expect(location_path).to eq("/users/auth/google_oauth2")
    expect(location_params["terms_accepted"]).to eq("true")
  end
end
