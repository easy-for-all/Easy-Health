module Api
  module V1
    class ProfileController < BaseController
      def update_avatar
        unless params[:avatar].present?
          return render json: { error: "No file uploaded" }, status: :unprocessable_entity
        end

        file = params[:avatar]
        unless file.content_type.start_with?("image/")
          return render json: { error: "Only image files are allowed" }, status: :unprocessable_entity
        end

        if file.size > 10.megabytes
          return render json: { error: "File too large (max 10MB)" }, status: :unprocessable_entity
        end

        current_user.avatar.attach(file)

        if current_user.avatar.attached?
          render json: { avatar_url: blob_path(current_user.avatar) }, status: :ok
        else
          render json: { error: "Upload failed" }, status: :unprocessable_entity
        end
      end
    end
  end
end
