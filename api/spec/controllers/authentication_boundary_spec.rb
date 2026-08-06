require "rails_helper"

# O modo anônimo abriu um segundo caminho de escrita no backend. Estes testes
# protegem a fronteira entre os dois.
#
# A regra: um controller ou EXIGE sessão (herda Api::V1::BaseController) ou é
# anônimo (herda ApplicationController). Nunca os dois. `skip_before_action
# :authenticate_user!` é o atalho que transforma "esta rota é pública" numa
# linha fácil de copiar para a rota errada — e uma rota autenticada que vira
# pública por engano não falha nenhum teste que já exista.
RSpec.describe "authentication boundary", type: :model do
  CONTROLLERS = Rails.root.join("app/controllers").glob("**/*.rb").freeze

  # Lista congelada, não proibição absoluta: estes quatro precisam mesmo rodar
  # sem sessão (é onde a sessão nasce, mais o link público de compartilhamento).
  # O que o teste protege é que a lista não CRESÇA por acidente — o modo anônimo
  # não está aqui de propósito, porque ele tem a própria autenticação.
  KNOWN_UNAUTHENTICATED = %w[
    app/controllers/api/v1/auth/google_native_controller.rb
    app/controllers/api/v1/auth/google_oauth_controller.rb
    app/controllers/api/v1/auth/mobile_callbacks_controller.rb
    app/controllers/api/v1/auth/omniauth_callbacks_controller.rb
    app/controllers/api/v1/shared_workouts_controller.rb
  ].freeze

  it "does not grow the set of controllers that skip authenticate_user!" do
    skippers = CONTROLLERS.select { |path| path.read.match?(/skip_before_action\s+:authenticate_user!/) }
                          .map { |path| path.relative_path_from(Rails.root).to_s }

    expect(skippers.sort).to eq(KNOWN_UNAUTHENTICATED.sort)
  end

  it "keeps AnonymousAuthentication out of the authenticated base controller" do
    base = Rails.root.join("app/controllers/api/v1/base_controller.rb").read

    expect(base).not_to include("AnonymousAuthentication")
    expect(base).to include("before_action :authenticate_user!")
  end

  # Todo controller anônimo tem que passar pelo concern. Um que herde
  # ApplicationController direto seria uma rota sem autenticação NENHUMA, o que
  # é diferente de "autenticada por token anônimo".
  it "authenticates every anonymous controller except the token mint" do
    anonymous = Rails.root.join("app/controllers/api/v1/anonymous").glob("*.rb")
    expect(anonymous).not_to be_empty

    anonymous.each do |path|
      source = path.read
      next if path.basename.to_s.in?(%w[base_controller.rb sessions_controller.rb])

      expect(source).to include("< BaseController"),
                        "#{path.basename} must inherit the anonymous BaseController"
    end
  end

  # O claim é o único endpoint do modo anônimo que precisa de uma conta de
  # verdade: current_user vem do cookie, a posse dos dados vem do token.
  it "keeps the claim endpoint authenticated" do
    source = Rails.root.join("app/controllers/api/v1/anonymous_claims_controller.rb").read

    expect(source).to include("< BaseController")
    expect(source).to include("current_user")
  end
end
