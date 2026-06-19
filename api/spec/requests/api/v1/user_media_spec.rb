require "rails_helper"

RSpec.describe "Api::V1::UserMedia", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def image_file(filename: "photo.jpg", content_type: "image/jpeg", size_mb: 1)
    Rack::Test::UploadedFile.new(
      StringIO.new("x" * (size_mb * 1.megabyte)),
      content_type,
      original_filename: filename
    )
  end

  def pdf_file(size_mb: 1)
    Rack::Test::UploadedFile.new(
      StringIO.new("%PDF-1.4 " + "x" * (size_mb * 1.megabyte)),
      "application/pdf",
      original_filename: "exam.pdf"
    )
  end

  describe "POST /api/v1/user_media" do
    context "body_photo" do
      it "accepts jpeg" do
        allow_any_instance_of(BodyPhotoValidationService).to receive(:call).and_return(
          double(has_human_body: true, has_face: false, rejection_reason: nil, face_bbox: nil)
        )
        allow_any_instance_of(BodyAnalysisService).to receive(:call).and_return(
          double(data_point: nil, observation: nil)
        )
        allow_any_instance_of(BodyCompositionAnalysisService).to receive(:call).and_return(
          double(data_point: nil, composition: nil)
        )

        post "/api/v1/user_media",
             params: { file: image_file, category: "body_photo", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:created)
      end

      it "accepts webp" do
        allow_any_instance_of(BodyPhotoValidationService).to receive(:call).and_return(
          double(has_human_body: true, has_face: false, rejection_reason: nil, face_bbox: nil)
        )
        allow_any_instance_of(BodyAnalysisService).to receive(:call).and_return(
          double(data_point: nil, observation: nil)
        )
        allow_any_instance_of(BodyCompositionAnalysisService).to receive(:call).and_return(
          double(data_point: nil, composition: nil)
        )

        post "/api/v1/user_media",
             params: { file: image_file(filename: "photo.webp", content_type: "image/webp"),
                       category: "body_photo", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:created)
      end

      it "rejects PDF" do
        post "/api/v1/user_media",
             params: { file: pdf_file, category: "body_photo", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to include("Invalid file type")
      end

      it "rejects file over 10MB" do
        post "/api/v1/user_media",
             params: { file: image_file(size_mb: 11), category: "body_photo", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to include("too large")
      end
    end

    context "exam" do
      it "accepts PDF" do
        allow_any_instance_of(ExamValidationService).to receive(:call).and_return(
          double(valid: true, rejection_reason: nil)
        )
        allow_any_instance_of(ExamDataExtractionService).to receive(:call).and_return(
          double(data_points: [])
        )

        post "/api/v1/user_media",
             params: { file: pdf_file, category: "exam", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:created)
      end

      it "accepts jpeg" do
        allow_any_instance_of(ExamValidationService).to receive(:call).and_return(
          double(valid: true, rejection_reason: nil)
        )
        allow_any_instance_of(ExamDataExtractionService).to receive(:call).and_return(
          double(data_points: [])
        )

        post "/api/v1/user_media",
             params: { file: image_file, category: "exam", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:created)
      end

      it "rejects webp" do
        post "/api/v1/user_media",
             params: { file: image_file(filename: "exam.webp", content_type: "image/webp"),
                       category: "exam", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to include("Invalid file type")
      end

      it "rejects file over 25MB" do
        post "/api/v1/user_media",
             params: { file: pdf_file(size_mb: 26), category: "exam", captured_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to include("too large")
      end
    end

    it "returns 422 when no file is sent" do
      post "/api/v1/user_media", params: { category: "body_photo", captured_at: Time.current.iso8601 }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/user_media/:id" do
    let!(:media) do
      m = create_user_media(user, category: "body_photo")
      m
    end

    it "destroys the record and schedules file purge" do
      expect_any_instance_of(ActiveStorage::Attached::One).to receive(:purge_later)
      delete "/api/v1/user_media/#{media.id}"
      expect(response).to have_http_status(:no_content)
      expect(UserMedia.find_by(id: media.id)).to be_nil
    end

    it "returns 404 for another user's media" do
      other = create(:user)
      other_media = create_user_media(other, category: "body_photo")
      delete "/api/v1/user_media/#{other_media.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  private

  def create_user_media(owner, category:)
    media = UserMedia.create!(
      user:        owner,
      category:    category,
      captured_at: Time.current
    )
    media.file.attach(
      io:           StringIO.new("fake image data"),
      filename:     "test.jpg",
      content_type: "image/jpeg"
    )
    media
  end
end
