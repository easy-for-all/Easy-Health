module Api
  module V1
    class DetailedProfilesController < BaseController
      def show
        profile     = current_user.health_profile
        data_points = current_user.health_data_points
                                  .where.not(status: "ignored")
                                  .order(collected_at: :desc, created_at: :desc)
        media_items = current_user.user_media.order(captured_at: :desc)

        render json: {
          physical:    profile_json(profile),
          data_points: data_points.map { |dp| data_point_json(dp) },
          media:       media_items.map  { |m|  media_json(m) },
        }
      end

      private

      def profile_json(profile)
        return nil unless profile

        h  = profile.height_cm.to_f
        w  = profile.weight_kg.to_f
        bmi = (h > 0 && w > 0) ? (w / ((h / 100.0) ** 2)).round(1) : nil

        {
          age:                    profile.age,
          weight_kg:              profile.weight_kg,
          height_cm:              profile.height_cm,
          fitness_level:          profile.fitness_level,
          goal:                   profile.goal,
          training_days_per_week: profile.training_days_per_week,
          training_location:      profile.training_location,
          modality:               profile.modality,
          bmi:                    bmi,
        }
      end

      def data_point_json(dp)
        {
          id:           dp.id,
          field_name:   dp.field_name,
          value:        dp.value,
          unit:         dp.unit,
          source_type:  dp.source_type,
          status:       dp.status,
          confidence:   dp.confidence,
          ai_notes:     dp.ai_notes,
          raw_text:     dp.raw_text,
          collected_at: dp.collected_at,
          created_at:   dp.created_at,
        }
      end

      def media_json(m)
        blob = m.file.attached? ? m.file.blob : nil
        {
          id:          m.id,
          category:    m.category,
          notes:       m.notes,
          captured_at: m.captured_at,
          file_url:    blob_path(m.file),
          file_name:   blob&.filename.to_s,
          file_size:   blob&.byte_size,
          mime_type:   blob&.content_type,
        }
      end
    end
  end
end
