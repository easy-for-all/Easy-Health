module Api
  module V1
    module Anonymous
      # Base de TODO endpoint anônimo.
      #
      # Herda de ApplicationController e não de Api::V1::BaseController — a mesma
      # escolha de Analytics::EventsController e App::InstallationsController.
      # A alternativa (herdar de BaseController e dar skip no authenticate_user!)
      # é o que transforma "esta rota é pública" numa linha fácil de copiar para
      # a rota errada. Aqui, ser anônimo é a herança, não uma exceção.
      #
      # Nada aqui roda AppInstallationReconciliation: não há usuário para
      # reconciliar, e o vínculo instalação→usuário acontece uma vez só, no
      # claim, sob a lógica de conflito de AppInstallations::LinkToUser.
      class BaseController < ApplicationController
        include AnonymousAuthentication

        private

        def render_anonymous_error(code, status, extra = {})
          render json: { error: code }.merge(extra), status: status
        end
      end
    end
  end
end
