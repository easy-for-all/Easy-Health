require "rails_helper"

# Smoke técnico do login Google, NÃO um E2E: nenhum teste aqui fala com o
# Google. O que se verifica é o contrato de rotas que o Web e o app Android
# dependem — a única parte do fluxo que um deploy pode quebrar sozinho e que
# ninguém percebe até alguém tentar entrar.
RSpec.describe "Google OAuth surface", type: :request do
  def route_for(path, method: :get)
    Rails.application.routes.recognize_path(path, method: method)
  end

  it "keeps the web initiation route" do
    expect(route_for("/auth/google/web")).to include(
      controller: "api/v1/auth/google_oauth", action: "web"
    )
  end

  it "keeps the Android initiation route pointing at the mobile OmniAuth strategy" do
    get "/auth/google/android"

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/users/auth/google_oauth2_mobile")
  end

  it "keeps the web callback" do
    expect(route_for("/users/auth/google_oauth2/callback")).to include(
      controller: "api/v1/auth/omniauth_callbacks", action: "google_oauth2"
    )
  end

  # O callback mobile é uma rota separada de propósito (ver devise.rb): a
  # decisão mobile-vs-web vem do provider, não de um query param que o Custom
  # Tab não preserva. Se esta rota sumir, o Android autentica e não volta.
  it "keeps the mobile callback that hands the app back a one-time code" do
    expect(route_for("/users/auth/google_oauth2_mobile/callback")).to include(
      controller: "api/v1/auth/omniauth_callbacks", action: "google_oauth2_mobile"
    )
  end

  it "keeps the endpoint that exchanges the mobile one-time code for a session" do
    expect(route_for("/api/v1/auth/mobile/exchange", method: :post)).to include(
      controller: "api/v1/auth/mobile_callbacks", action: "exchange"
    )
  end

  # O caminho do plugin nativo (@capgo/capacitor-social-login), que não passa
  # por navegador nenhum.
  it "keeps the native Google endpoint used by the Capacitor plugin" do
    expect(route_for("/api/v1/auth/google/native", method: :post)).to include(
      controller: "api/v1/auth/google_native", action: "create"
    )
  end

  it "keeps the OmniAuth failure route" do
    expect(route_for("/users/auth/failure")).to include(
      controller: "api/v1/auth/omniauth_callbacks", action: "failure"
    )
  end
end
