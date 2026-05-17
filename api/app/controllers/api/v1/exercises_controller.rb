module Api
  module V1
    class ExercisesController < BaseController
      def index
        exercises = Exercise.all
        exercises = exercises.where(muscle_group: params[:muscle_group]) if params[:muscle_group].present?
        exercises = exercises.where(exercise_type: params[:exercise_type]) if params[:exercise_type].present?
        exercises = exercises.where(equipment_type: params[:equipment_type]) if params[:equipment_type].present?
        if params[:name].present?
          term = "%#{params[:name]}%"
          exercises = exercises.where("name ILIKE ? OR description ILIKE ?", term, term)
        end
        exercises = exercises.where.not(id: params[:exclude_ids].to_s.split(",")) if params[:exclude_ids].present?

        render json: exercises.map { |e| exercise_json(e) }
      end

      def setup_guide
        exercise = Exercise.find(params[:id])
        guide = exercise.setup_guide.presence || ExerciseSetupGuideService.new(exercise).call
        if guide
          render json: { setup_guide: guide }
        else
          render json: { error: "Não foi possível gerar o guia" }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def ai_substitute
        unless params[:image].present?
          return render json: { error: "No image provided" }, status: :unprocessable_entity
        end

        file     = params[:image]
        exercise = Exercise.find(params[:exercise_id])
        candidates = Exercise.where(muscle_group: exercise.muscle_group)
                             .or(Exercise.where(exercise_type: exercise.exercise_type))
                             .where.not(id: exercise.id)
                             .limit(20)

        suggestions = ExerciseSubstituteService.new(
          image_data:   file.read,
          content_type: file.content_type,
          exercise:     exercise,
          candidates:   candidates
        ).call

        render json: { suggestions: suggestions.map { |e| exercise_json(e) } }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      private

      include ExerciseImageHelper

      def exercise_json(exercise)
        {
          id: exercise.id,
          name: exercise.name,
          muscle_group: exercise.muscle_group,
          exercise_type: exercise.exercise_type,
          equipment_type: exercise.equipment_type,
          description: exercise.description,
          instructions: exercise.instructions,
          image_url: exercise_image_url(exercise),
          gif_url: exercise.gif_url,
          video_url: exercise.video_url,
          muscle_image_url: muscle_image_url(exercise.muscle_group)
        }
      end
    end
  end
end
