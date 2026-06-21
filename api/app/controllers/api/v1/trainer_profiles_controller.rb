module Api
  module V1
    class TrainerProfilesController < BaseController
      before_action :require_personal_trainer!

      # GET /api/v1/trainer/profile
      def show
        profile = current_user.trainer_profile
        if profile
          render json: serialize(profile)
        else
          render json: { profile: nil }
        end
      end

      # POST /api/v1/trainer/profile
      def create
        if current_user.trainer_profile.present?
          render json: { errors: ["Perfil já existe. Use PATCH para atualizar."] }, status: :unprocessable_entity
          return
        end
        profile = current_user.build_trainer_profile(trainer_profile_params)
        if profile.save
          render json: serialize(profile), status: :created
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/trainer/profile
      def update
        profile = current_user.trainer_profile || current_user.build_trainer_profile
        if profile.update(trainer_profile_params)
          render json: serialize(profile)
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def trainer_profile_params
        params.permit(:display_name, :bio, :cref, :status)
      end

      def serialize(profile)
        {
          id:           profile.id,
          display_name: profile.display_name,
          bio:          profile.bio,
          cref:         profile.cref,
          status:       profile.status,
          updated_at:   profile.updated_at&.iso8601,
        }
      end
    end
  end
end
