module Api
  module V1
    module Anonymous
      # As respostas do wizard, guardadas como jsonb na sessão anônima.
      #
      # Não cria HealthProfile: essa tabela é escopada em usuário e uma linha
      # órfã ali seria lixo que o claim depois teria que reconciliar. O jsonb é
      # exatamente o que o claim replica numa HealthProfile de verdade.
      class ProfilesController < BaseController
        # PUT /api/v1/anonymous/profile
        def update
          answers = permitted_answers
          return render json: { error: "profile_answers_required" }, status: :unprocessable_entity if answers.blank?

          anonymous_session.update!(profile_answers: anonymous_session.profile_answers.merge(answers))

          render json: { profile_answers: anonymous_session.profile_answers }, status: :ok
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: "profile_invalid", details: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        private

        # Allowlist derivada do schema de health_profiles. Sem ela, o jsonb
        # aceitaria qualquer chave e o claim tentaria escrever atributos que não
        # existem — falhando no cadastro, que é o pior momento possível.
        def permitted_answers
          params.permit(*Workouts::InstallationOwner.profile_attribute_names)
                .to_h
                .reject { |_key, value| value.nil? }
        end
      end
    end
  end
end
