require "rails_helper"

# O shell iOS carrega os assets do próprio IPA, então a origem dele é
# capacitor://localhost — nunca easyhealth.art. Estes specs fixam que essa
# origem é aceita de forma restrita e que aceitá-la não afrouxou nada.
RSpec.describe "CORS", type: :request do
  NATIVE_ORIGINS = ["capacitor://localhost", "ionic://localhost", "http://localhost"].freeze

  def preflight(origin, method: "GET", headers: "authorization,content-type")
    process(
      :options, "/api/v1/auth/me",
      headers: {
        "HTTP_ORIGIN" => origin,
        "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => method,
        "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => headers
      }
    )
  end

  describe "native origins" do
    NATIVE_ORIGINS.each do |origin|
      it "allows #{origin}" do
        preflight(origin)

        expect(response.headers["Access-Control-Allow-Origin"]).to eq(origin)
      end

      # credentials: false é a decisão central. Se isto virasse "true", a origem
      # local passaria a carregar a sessão de cookie do domínio principal — que
      # é exatamente o afrouxamento que este desenho existe para evitar.
      it "does NOT allow credentials for #{origin}" do
        preflight(origin)

        expect(response.headers["Access-Control-Allow-Credentials"]).to be_nil
      end
    end

    it "permits the Authorization header, which is how the native shell authenticates" do
      preflight("capacitor://localhost", headers: "authorization")

      allowed = response.headers["Access-Control-Allow-Headers"].to_s.downcase
      expect(allowed).to include("authorization")
    end

    it "permits Content-Type" do
      preflight("capacitor://localhost", headers: "content-type")

      allowed = response.headers["Access-Control-Allow-Headers"].to_s.downcase
      expect(allowed).to include("content-type")
    end

    it "permits the verbs the API actually uses" do
      %w[GET POST PATCH DELETE].each do |verb|
        preflight("capacitor://localhost", method: verb)

        expect(response.headers["Access-Control-Allow-Methods"].to_s.upcase).to include(verb)
      end
    end
  end

  describe "everything else" do
    it "never answers with a wildcard origin" do
      preflight("capacitor://localhost")

      expect(response.headers["Access-Control-Allow-Origin"]).not_to eq("*")
    end

    it "rejects an origin that is not on the allowlist" do
      preflight("https://evil.example.com")

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end

    it "rejects a lookalike of the native origin" do
      preflight("capacitor://localhost.evil.com")

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end
end
