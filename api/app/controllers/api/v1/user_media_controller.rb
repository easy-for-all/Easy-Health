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

        category = params[:category].to_s
        file_data = file.read

        case category
        when "body_photo"
          result, file_data = validate_and_process_body_photo(file_data, file.content_type)
          return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]
        when "exam"
          result = validate_exam(file_data, file.content_type)
          return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]
        end

        media = current_user.user_media.build(
          category:    category,
          notes:       params[:notes],
          captured_at: params[:captured_at] || Time.current
        )
        media.file.attach(
          io:           StringIO.new(file_data),
          filename:     file.original_filename,
          content_type: file.content_type
        )

        if media.save
          render json: media_json(media).merge(face_blurred: result&.dig(:face_blurred) || false), status: :created
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

      def validate_and_process_body_photo(file_data, content_type)
        validation = BodyPhotoValidationService.new(
          image_data:   file_data,
          content_type: content_type
        ).call

        unless validation.has_human_body
          reason = validation.rejection_reason.presence ||
                   "A imagem não contém um corpo humano identificável."
          return [{ error: "Foto rejeitada: #{reason} Envie uma foto com corpo humano identificável." }, file_data]
        end

        face_blurred = false
        if validation.has_face
          processed = FaceBlurService.new(
            image_data: file_data,
            face_bbox:  validation.face_bbox,
            has_face:   validation.has_face
          ).call
          file_data    = processed
          face_blurred = true
        end

        [{ face_blurred: face_blurred }, file_data]
      end

      def validate_exam(file_data, content_type)
        validation = ExamValidationService.new(
          file_data:    file_data,
          content_type: content_type
        ).call

        unless validation.valid
          reason = validation.rejection_reason.presence ||
                   "O arquivo não parece ser um exame ou documento de saúde."
          return { error: "Arquivo rejeitado: #{reason} Envie apenas exames clínicos, bioimpedâncias ou documentos de saúde." }
        end

        {}
      end

      def media_json(media)
        blob = media.file.attached? ? media.file.blob : nil
        {
          id:          media.id,
          category:    media.category,
          notes:       media.notes,
          captured_at: media.captured_at,
          file_url:    blob_path(media.file),
          file_name:   blob&.filename.to_s,
          file_size:   blob&.byte_size,
          mime_type:   blob&.content_type
        }
      end
    end
  end
end
