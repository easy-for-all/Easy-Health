module Api
  module V1
    class UserMediaController < BaseController
      def index
        media = current_user.user_media.order(captured_at: :desc)
        render json: media.map { |m| media_json(m) }
      end

      def create
        unless params[:file].present?
          return render json: { error: "No file uploaded" }, status: :unprocessable_entity
        end

        file = params[:file]
        unless file.content_type.start_with?("image/") || file.content_type == "application/pdf"
          return render json: { error: "Only images and PDFs are allowed" }, status: :unprocessable_entity
        end

        if file.size > 20.megabytes
          return render json: { error: "File too large (max 20MB)" }, status: :unprocessable_entity
        end

        media = current_user.user_media.build(
          category: params[:category],
          notes: params[:notes],
          captured_at: params[:captured_at] || Time.current
        )
        media.file.attach(file)

        if media.save
          render json: media_json(media), status: :created
        else
          render json: { errors: media.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        media = current_user.user_media.find(params[:id])
        media.file.purge_later if media.file.attached?
        media.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def media_json(media)
        blob = media.file.attached? ? media.file.blob : nil
        {
          id: media.id,
          category: media.category,
          notes: media.notes,
          captured_at: media.captured_at,
          file_url: blob_path(media.file),
          file_name: blob&.filename.to_s,
          file_size: blob&.byte_size,
          mime_type: blob&.content_type
        }
      end
    end
  end
end
